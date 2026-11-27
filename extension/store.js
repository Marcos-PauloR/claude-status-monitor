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

// Conta do snapshot ou do evento de compact (v1.3): sem campo = default; saneada como na ponte.
export function accountOf(o) {
    const a = o?.account;
    return typeof a === 'string' && a ? a.replace(/[^A-Za-z0-9_-]/g, '_') : 'default';
}
const accountOrder = (a, b) => (a === b ? 0 : a === 'default' ? -1 : b === 'default' ? 1 : a < b ? -1 : 1);

// Conteúdo de compacts.jsonl -> [{ts, account}]. Linhas inválidas são ignoradas.
export function parseCompactEvents(text) {
    const events = [];
    for (const line of text.split('\n')) {
        try {
            const e = JSON.parse(line);
            const t = num(e?.ts);
            if (t !== null)
                events.push({ts: t, account: accountOf(e)});
        } catch {}
    }
    return events;
}

// Lê compacts.jsonl com a conta de cada evento. Ausente ou ilegível vira lista vazia.
export function readCompactEvents(path = compactsFile()) {
    try {
        const [, bytes] = Gio.File.new_for_path(path).load_contents(null);
        return parseCompactEvents(new TextDecoder().decode(bytes));
    } catch (e) {
        if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND))
            console.warn(`claude-status: ignorando compacts.jsonl: ${e.message}`);
        return [];
    }
}

// Janela fixada no painel (v1.3): uma linha com o session_id saneado.
export function pinnedFile() {
    return GLib.build_filenamev([dataDir(), 'pinned']);
}

export function readPinned(path = pinnedFile()) {
    try {
        const [, bytes] = Gio.File.new_for_path(path).load_contents(null);
        const id = new TextDecoder().decode(bytes).split('\n')[0].trim().replace(/[^A-Za-z0-9_-]/g, '_');
        return id || null;
    } catch {
        return null;
    }
}

// file_set_contents grava num temporário e renomeia (escrita atômica).
export function writePinned(id, path = pinnedFile()) {
    try {
        GLib.mkdir_with_parents(GLib.path_get_dirname(path), 0o755);
        GLib.file_set_contents(path, `${String(id).replace(/[^A-Za-z0-9_-]/g, '_')}\n`);
    } catch (e) {
        console.warn(`claude-status: não foi possível gravar ${path}: ${e.message}`);
    }
}

export function clearPinned(path = pinnedFile()) {
    try {
        Gio.File.new_for_path(path).delete(null);
    } catch (e) {
        if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND))
            console.warn(`claude-status: não foi possível apagar ${path}: ${e.message}`);
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
 * Resumo para o painel e o menu (RF01–RF07; contas e janela fixada na v1.3).
 * @param {Iterable<object>} snapshots
 * @param {number} now epoch em segundos
 * @param {{inactiveMinutes?: number, warn?: number, crit?: number,
 *          thresholds?: Object<string, {warn: number, crit: number}>,
 *          pinned?: string|null, labels?: Object<string, string>, events?: {ts: number, account: string}[]}} opts
 *   warn/crit são os limiares gerais; `thresholds` sobrescreve por indicador (ctx, session, weekly).
 *   `pinned` é o id (saneado) da janela fixada; `labels` são os apelidos das contas; `events` vêm de
 *   readCompactEvents().
 * @returns {null | {model, ctx, compacts, session, sessionResets, weekly, level, levels, active, windows,
 *                   quotas, weekStart, weekCompacts, focus, accounts, multi, pinnedValid}}
 *   Os campos do topo são da janela em foco (fixada ou mais recente) e da conta dela.
 */
export function summarize(snapshots, now, opts = {}) {
    const {inactiveMinutes = 15, warn = 70, crit = 90, thresholds = {}, pinned = null, labels = {}, events = []} = opts;
    const lv = (key, p) => level(p, {warn, crit, ...thresholds[key]});
    const all = [...snapshots].filter(Boolean).sort((a, b) => b.updated_at - a.updated_at);
    const active = all.filter(s => now - s.updated_at < inactiveMinutes * 60);
    if (active.length === 0)
        return null;

    const pinnedSnap = pinned ? active.find(s => s.session_id.replace(/[^A-Za-z0-9_-]/g, '_') === pinned) : null;
    const toWindow = w => ({
        id: w.session_id,
        account: accountOf(w),
        pinned: w === pinnedSnap,
        project: w.project ?? null,
        name: w.session_name ?? null,
        model: w.model ?? null,
        ctx: num(w.context?.used_pct),
        tokens: num(w.context?.tokens),
        window: num(w.context?.window),
        compacts: num(w.compacts) ?? 0,
        level: lv('ctx', w.context?.used_pct),
    });
    const windows = active.map(toWindow);

    // A cota é da conta: vale o snapshot mais recente dela que a tenha, mesmo de janela inativa.
    // Conta listada = tem janela ativa ou cota ainda não resetada de um snapshot de até 7 dias
    // (cota sem resets_at nunca reseta e listaria a conta para sempre).
    const ids = [...new Set(all.map(accountOf))].sort(accountOrder);
    const accounts = ids.map(id => {
        const withLimits = all.find(s => accountOf(s) === id && s.limits);
        const session = quota(withLimits?.limits?.five_hour, now);
        const weekly = quota(withLimits?.limits?.seven_day, now);
        const since = weekStart(withLimits?.limits, now);
        const levels = {session: lv('session', session?.pct), weekly: lv('weekly', weekly?.pct)};
        return {
            id,
            label: labels[id] ?? id,
            session: session?.pct ?? null,
            sessionResets: session?.resetsIn ?? null,
            weekly: weekly?.pct ?? null,
            quotas: {session, weekly},
            weekStart: since,
            weekCompacts: events.filter(e => e.account === id && e.ts >= since).length,
            level: Math.max(levels.session, levels.weekly),
            levels,
            windows: windows.filter(w => w.account === id),
            fresh: !!withLimits && now - withLimits.updated_at < WEEK,
        };
    }).filter(a => a.windows.length > 0
        || (a.fresh && (a.quotas.session?.reset === false || a.quotas.weekly?.reset === false)))
        .map(({fresh, ...a}) => a);

    const focusSnap = pinnedSnap ?? active[0];
    const focus = windows[active.indexOf(focusSnap)];
    const acc = accounts.find(a => a.id === focus.account);
    const levels = {ctx: focus.level, session: acc.levels.session, weekly: acc.levels.weekly};
    return {
        model: focusSnap.model ?? 'Claude',
        ctx: focus.ctx,
        compacts: focus.compacts,
        session: acc.session,
        sessionResets: acc.sessionResets,
        weekly: acc.weekly,
        level: Math.max(levels.ctx, levels.session, levels.weekly),
        levels,
        active,
        windows,
        quotas: acc.quotas,
        weekStart: acc.weekStart,
        weekCompacts: acc.weekCompacts,
        focus,
        accounts,
        multi: accounts.length > 1,
        pinnedValid: !pinned || !!pinnedSnap,
    };
}
