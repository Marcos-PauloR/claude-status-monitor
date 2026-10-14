.pragma library
// Formatação do plasmoid. Os números já vêm calculados por claude-status-summary.sh --format json,
// que também diz o idioma (lang) e os limiares (warn, crit) resolvidos a partir do config único.

// Textos em inglês (chave) e português; o resto do plasmoid passa tudo por tr().
const PT = {
    "session": "sessão",
    "weekly": "semana",
    "resets": "reinicia",
    "compacts": "compactações",
    "resets in": "reinicia em",
    "just reset": "reiniciada",
    "no data yet": "sem dados ainda",
    "compacts this week": "compactações na semana",
    "no active windows": "nenhuma janela ativa",
    "(no project)": "(sem projeto)",
    "Open data folder": "Abrir pasta de dados",
    // configuração
    "Yellow from (%):": "Amarelo a partir de (%):",
    "Red from (%):": "Vermelho a partir de (%):",
    "Hide windows after (minutes):": "Esconder janelas após (minutos):",
    "Refresh every (seconds):": "Atualizar a cada (segundos):",
    "Language:": "Idioma:",
    "from config": "do config",
    "Values shown as \"from config\" follow ~/.config/claude-status/config (install.sh --warn, --crit, --inactive, --lang).":
        "Os valores \"do config\" seguem ~/.config/claude-status/config (install.sh --warn, --crit, --inactive, --lang).",
};

function tr(lang, text) {
    return lang === "pt" && PT[text] !== undefined ? PT[text] : text;
}

// Idioma antes do primeiro resumo (ou na tela de configuração): o escolhido no plasmoid ou o do sistema.
function fallbackLang(chosen, localeName) {
    if (chosen === "en" || chosen === "pt")
        return chosen;
    return String(localeName || "").startsWith("pt") ? "pt" : "en";
}

// Argumentos do resumidor: só o que foi mudado no plasmoid (0 / vazio = segue o config único).
function summaryArgs(cfg) {
    const args = ["--format", "json"];
    if (cfg.warnThreshold > 0)
        args.push("--warn", cfg.warnThreshold);
    if (cfg.critThreshold > 0)
        args.push("--crit", cfg.critThreshold);
    if (cfg.inactiveMinutes > 0)
        args.push("--inactive", cfg.inactiveMinutes);
    if (cfg.language === "en" || cfg.language === "pt")
        args.push("--lang", cfg.language);
    return args.join(" ");
}

// Nível de cor de uma porcentagem com os limiares do resumo (padrão 70/90).
function level(p, s) {
    if (typeof p !== "number")
        return 0;
    const warn = s && typeof s.warn === "number" ? s.warn : 70;
    const crit = s && typeof s.crit === "number" ? s.crit : 90;
    return p >= crit ? 2 : p >= warn ? 1 : 0;
}

function duration(seconds) {
    if (seconds === null || seconds === undefined || seconds < 0)
        return "—";
    const m = Math.floor(seconds / 60);
    if (m < 60)
        return m + "m";
    const h = Math.floor(m / 60);
    if (h < 24)
        return h + "h" + String(m % 60).padStart(2, "0");
    return Math.floor(h / 24) + "d" + (h % 24) + "h";
}

function tokens(n) {
    if (typeof n !== "number")
        return "—";
    if (n >= 1e6)
        return Number((n / 1e6).toFixed(1)) + "M";
    if (n >= 1e3)
        return Math.round(n / 1e3) + "k";
    return String(n);
}

function pct(v) {
    return typeof v === "number" ? v + "%" : "—";
}

// Texto do painel: ctx · session · resets · weekly (os que existirem), no idioma do resumo.
function panelText(s) {
    if (!s || s.empty)
        return "Claude —";
    const parts = [];
    if (typeof s.ctx === "number")
        parts.push("ctx " + s.ctx + "%");
    if (s.session) {
        parts.push(tr(s.lang, "session") + " " + s.session.pct + "%");
        parts.push(tr(s.lang, "resets") + " " + duration(s.session.resets_in));
    }
    if (s.weekly)
        parts.push(tr(s.lang, "weekly") + " " + s.weekly.pct + "%");
    return parts.length ? parts.join(" · ") : (s.model || "Claude");
}

function windowTitle(w, lang) {
    return [w.project || tr(lang, "(no project)"), w.name].filter(Boolean).join(" — ");
}

function quotaDetail(q, lang) {
    if (!q)
        return tr(lang, "no data yet");
    return q.pct + "%  " + (q.reset ? tr(lang, "just reset") : tr(lang, "resets in") + " " + duration(q.resets_in));
}
