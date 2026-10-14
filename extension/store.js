// Leitura dos snapshots da ponte e cálculo do que o painel mostra.
// Não depende do GNOME Shell (só Gio/GLib), então roda nos testes com `gjs -m`.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

export const SCHEMA = 1;

export function dataDir() {
    return GLib.build_filenamev([GLib.get_user_cache_dir(), 'claude-status']);
}

export function sessionsDir() {
    return GLib.build_filenamev([dataDir(), 'sessions']);
}

export function compactsFile() {
    return GLib.build_filenamev([dataDir(), 'compacts.jsonl']);
}

// Arquivos começados com '.' são temporários da escrita atômica da ponte.
export function isSnapshotName(name) {
    return !!name && !name.startsWith('.') && name.endsWith('.json');
}

// Valida o contrato v1. Retorna o snapshot ou lança um Error com o motivo.
export function parseSnapshot(text) {
    const s = JSON.parse(text);
    if (!s || typeof s !== 'object')
        throw new Error('não é um objeto');
    if (s.schema !== SCHEMA)
        throw new Error(`schema ${s.schema} não suportado`);
    if (typeof s.session_id !== 'string' || typeof s.updated_at !== 'number')
        throw new Error('session_id/updated_at ausentes');
    return s;
}

// Lê e valida um arquivo. Retorna null (com log) se estiver ausente ou inválido.
export function readSnapshot(file) {
    try {
        const [, bytes] = file.load_contents(null);
        return parseSnapshot(new TextDecoder().decode(bytes));
    } catch (e) {
        if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND))
            console.warn(`claude-status: ignorando ${file.get_basename()}: ${e.message}`);
        return null;
    }
}

const WEEK = 7 * 86400;

const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : null);

// Cota com reset já passado vale 0% (RF07).
function quota(window, now) {
    if (!window || num(window.used_pct) === null)
        return null;
    const resetsAt = num(window.resets_at);
    if (resetsAt !== null && resetsAt <= now)
        return {pct: 0, resetsIn: null, reset: true};
    return {pct: window.used_pct, resetsIn: resetsAt === null ? null : resetsAt - now, reset: false};
}

// "900", "55k", "1M", "1.5M".
export function formatTokens(n) {
    if (num(n) === null)
        return '—';
    if (n >= 1e6)
        return `${Number((n / 1e6).toFixed(1))}M`;
    if (n >= 1e3)
        return `${Math.round(n / 1e3)}k`;
    return String(n);
}

// Conteúdo de compacts.jsonl -> lista de `ts`. Linhas inválidas são ignoradas.
export function parseCompacts(text) {
    const ts = [];
    for (const line of text.split('\n')) {
        try {
            const t = num(JSON.parse(line)?.ts);
            if (t !== null)
                ts.push(t);
        } catch {}
    }
    return ts;
}

// Lê compacts.jsonl. Ausente ou ilegível vira lista vazia.
export function readCompacts(path = compactsFile()) {
    try {
        const [, bytes] = Gio.File.new_for_path(path).load_contents(null);
        return parseCompacts(new TextDecoder().decode(bytes));
    } catch (e) {
        if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND))
            console.warn(`claude-status: ignorando compacts.jsonl: ${e.message}`);
        return [];
    }
}

// Início da janela semanal atual (RF09): resets_at − 7 dias; sem limits, os últimos 7 dias.
export function weekStart(limits, now) {
    const resetsAt = num(limits?.seven_day?.resets_at);
    if (resetsAt === null)
        return now - WEEK;
    return resetsAt <= now ? resetsAt : resetsAt - WEEK;
}

export function countSince(tsList, since) {
    return tsList.filter(t => t >= since).length;
}

// "1h12", "45m", "2d3h". null/negativo vira "—".
export function formatDuration(seconds) {
    if (seconds === null || seconds === undefined || seconds < 0)
        return '—';
    const m = Math.floor(seconds / 60);
    if (m < 60)
        return `${m}m`;
    const h = Math.floor(m / 60);
    if (h < 24)
        return `${h}h${String(m % 60).padStart(2, '0')}`;
    return `${Math.floor(h / 24)}d${h % 24}h`;
}

// Nível de alerta de uma porcentagem: 0 normal, 1 aviso, 2 crítico (RF02).
export function level(pct, thresholds = {warn: 70, crit: 90}) {
    if (num(pct) === null)
        return 0;
    if (pct >= thresholds.crit)
        return 2;
    return pct >= thresholds.warn ? 1 : 0;
}

/**
 * Resumo para o painel e o menu (RF01–RF07).
 * @param {Iterable<object>} snapshots
 * @param {number} now epoch em segundos
 * @param {{inactiveMinutes?: number, warn?: number, crit?: number}} opts
 * @returns {null | {model, ctx, compacts, session, sessionResets, weekly, level, active, windows, quotas, weekStart}}
 */
export function summarize(snapshots, now, opts = {}) {
    const {inactiveMinutes = 15, warn = 70, crit = 90} = opts;
    const all = [...snapshots].filter(Boolean).sort((a, b) => b.updated_at - a.updated_at);
    const active = all.filter(s => now - s.updated_at < inactiveMinutes * 60);
    if (active.length === 0)
        return null;

    // A cota é da conta: vale o snapshot mais recente que a tenha, mesmo de janela inativa.
    const latest = active[0];
    const withLimits = all.find(s => s.limits);
    const session = quota(withLimits?.limits?.five_hour, now);
    const weekly = quota(withLimits?.limits?.seven_day, now);
    const ctx = num(latest.context?.used_pct);
    const lv = p => level(p, {warn, crit});

    return {
        model: latest.model ?? 'Claude',
        ctx,
        compacts: num(latest.compacts) ?? 0,
        session: session?.pct ?? null,
        sessionResets: session?.resetsIn ?? null,
        weekly: weekly?.pct ?? null,
        level: Math.max(...[ctx, session?.pct, weekly?.pct].map(lv)),
        active,
        windows: active.map(w => ({
            id: w.session_id,
            project: w.project ?? null,
            name: w.session_name ?? null,
            model: w.model ?? null,
            ctx: num(w.context?.used_pct),
            tokens: num(w.context?.tokens),
            window: num(w.context?.window),
            compacts: num(w.compacts) ?? 0,
            level: lv(w.context?.used_pct),
        })),
        quotas: {session, weekly},
        weekStart: weekStart(withLimits?.limits, now),
    };
}
