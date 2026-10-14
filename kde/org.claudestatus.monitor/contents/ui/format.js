.pragma library
// Formatação do plasmoid. Os números já vêm calculados por claude-status-summary.sh --format json.

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

// Texto do painel: ctx · session · resets · weekly (os que existirem).
function panelText(s) {
    if (!s || s.empty)
        return "Claude —";
    const parts = [];
    if (typeof s.ctx === "number")
        parts.push("ctx " + s.ctx + "%");
    if (s.session) {
        parts.push("session " + s.session.pct + "%");
        parts.push("resets " + duration(s.session.resets_in));
    }
    if (s.weekly)
        parts.push("weekly " + s.weekly.pct + "%");
    return parts.length ? parts.join(" · ") : (s.model || "Claude");
}

function windowTitle(w) {
    return [w.project || "(no project)", w.name].filter(Boolean).join(" — ");
}

function quotaDetail(q) {
    if (!q)
        return "no data yet";
    return q.pct + "%  " + (q.reset ? "just reset" : "resets in " + duration(q.resets_in));
}
