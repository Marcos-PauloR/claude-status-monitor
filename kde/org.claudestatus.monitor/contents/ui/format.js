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
    "Pin to panel": "Fixar no painel",
    "Unpin": "Desafixar",
    "account": "conta",
    // configuração
    "Yellow from (%):": "Amarelo a partir de (%):",
    "Red from (%):": "Vermelho a partir de (%):",
    "Hide windows after (minutes):": "Esconder janelas após (minutos):",
    "Refresh every (seconds):": "Atualizar a cada (segundos):",
    "Language:": "Idioma:",
    "from config": "do config",
    "Theme:": "Tema:",
    "Accounts in panel:": "Contas no painel:",
    "Account of the focused window": "Conta da janela em foco",
    "All accounts": "Todas as contas",
    "Values shown as \"from config\" follow ~/.config/claude-status/config (install.sh --warn, --crit, --inactive, --lang, --theme, --panel-accounts).":
        "Os valores \"do config\" seguem ~/.config/claude-status/config (install.sh --warn, --crit, --inactive, --lang, --theme, --panel-accounts).",
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
    if (/^[A-Za-z0-9_-]+$/.test(cfg.theme || ""))
        args.push("--theme", cfg.theme);
    if (cfg.panelAccounts === "focus" || cfg.panelAccounts === "all")
        args.push("--panel-accounts", cfg.panelAccounts);
    return args.join(" ");
}

// O tema "default" (ou resumo sem tema) mantém a aparência da v1.2: cores do Plasma, sem pintar.
function customTheme(theme) {
    return !!theme && theme.id !== "default";
}

// Cor de um tema que não seja o default; "" = não pinta (usa a do desktop).
function themed(theme, key) {
    return customTheme(theme) && theme[key] ? theme[key] : "";
}

// Cor de um nível (0/1/2). fallback = [texto, neutral, negative] do Kirigami (ou só a cor do texto).
// Tema default/sem tema: as cores do Kirigami da v1.2; outro tema: as dele, vazia = cor do texto.
function levelColor(theme, level, fallback) {
    const fb = Array.isArray(fallback) ? fallback : [fallback, fallback, fallback];
    if (!customTheme(theme))
        return fb[level] || fb[0];
    return [theme.normal, theme.warn, theme.crit][level] || fb[0];
}

// Cor da barra: bar no nível 0, warn/crit nos níveis 1/2; "" (default ou vazia) = barra do Breeze.
function barColor(theme, level) {
    return themed(theme, ["bar", "warn", "crit"][level] || "bar");
}

// Comando de fixar/desafixar uma janela (o resumidor grava/apaga ~/.cache/claude-status/pinned).
function pinCommand(w) {
    if (w.pinned)
        return "claude-status-summary.sh --unpin";
    return "claude-status-summary.sh --pin " + String(w.id || "").replace(/[^A-Za-z0-9_-]/g, "_");
}

// Apelido da conta da janela em foco (o resumidor já resolve account.<id> do config).
function accountLabel(s) {
    const id = s && s.focus && s.focus.account ? s.focus.account : "default";
    const a = (s && s.accounts || []).find(x => x.id === id);
    return a && a.label ? a.label : id;
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
// Com mais de uma conta: em "focus" o apelido da conta vem primeiro; em "all" é o mesmo texto do
// resumidor (model · ctx · <apelido> session%/weekly% por conta).
function panelText(s) {
    if (!s || s.empty)
        return "Claude —";
    if (s.multi && s.panel_accounts === "all") {
        const all = [s.model || "Claude"];
        if (typeof s.ctx === "number")
            all.push("ctx " + s.ctx + "%");
        for (const a of s.accounts || [])
            all.push(a.label + " " + pct(a.session && a.session.pct) + "/" + pct(a.weekly && a.weekly.pct));
        return all.join(" · ");
    }
    const parts = s.multi ? [accountLabel(s)] : [];
    if (typeof s.ctx === "number")
        parts.push("ctx " + s.ctx + "%");
    if (s.session) {
        parts.push(tr(s.lang, "session") + " " + s.session.pct + "%");
        parts.push(tr(s.lang, "resets") + " " + duration(s.session.resets_in));
    }
    if (s.weekly)
        parts.push(tr(s.lang, "weekly") + " " + s.weekly.pct + "%");
    if (s.multi && parts.length === 1)
        parts.push(s.model || "Claude");
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
