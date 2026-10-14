// Testes dos helpers do plasmoid (contents/ui/format.js) fora do Plasma. Uso: gjs -m kde/test.js
import GLib from 'gi://GLib';
import System from 'system';

// format.js é uma biblioteca JS do QML (".pragma library"): tira a diretiva e avalia.
const path = GLib.build_filenamev([GLib.path_get_dirname(import.meta.url.replace('file://', '')),
    'org.claudestatus.monitor', 'contents', 'ui', 'format.js']);
const src = new TextDecoder().decode(GLib.file_get_contents(path)[1]).replace(/^\.pragma library\s*$/m, '');
const F = new Function(`${src}; return {duration, tokens, pct, panelText, windowTitle, quotaDetail};`)();

let pass = 0, fail = 0;
function eq(desc, expected, actual) {
    const e = JSON.stringify(expected), a = JSON.stringify(actual);
    if (e === a) { pass++; print(`  ok   ${desc}`); } else { fail++; print(`  FAIL ${desc}\n       esperado: ${e} obtido: ${a}`); }
}

print('== duration / tokens / pct');
eq('minutos', '45m', F.duration(45 * 60 + 59));
eq('horas', '1h12', F.duration(4320));
eq('dias', '3d4h', F.duration(3 * 86400 + 4 * 3600));
eq('nulo', '—', F.duration(null));
eq('tokens k', '55k', F.tokens(54820));
eq('tokens M', '1.5M', F.tokens(1500000));
eq('tokens nulo', '—', F.tokens(null));
eq('pct', '42%', F.pct(42));
eq('pct nulo', '—', F.pct(null));

print('== panelText');
eq('vazio', 'Claude —', F.panelText(null));
eq('vazio (empty)', 'Claude —', F.panelText({empty: true}));
eq('completo', 'ctx 75% · session 31% · resets 1h12 · weekly 92%', F.panelText({
    empty: false, model: 'Opus 5.5', ctx: 75, session: {pct: 31, resets_in: 4320}, weekly: {pct: 92}}));
eq('sem limits', 'ctx 10%', F.panelText({empty: false, model: 'Opus 5.5', ctx: 10, session: null, weekly: null}));
eq('sem nada: modelo', 'Opus 5.5', F.panelText({empty: false, model: 'Opus 5.5', ctx: null, session: null, weekly: null}));

print('== windowTitle / quotaDetail');
eq('projeto e nome', 'my-app — core', F.windowTitle({project: 'my-app', name: 'core'}));
eq('sem projeto', '(no project)', F.windowTitle({project: null, name: null}));
eq('cota com reset', '31%  resets in 1h12', F.quotaDetail({pct: 31, resets_in: 4320, reset: false}));
eq('cota reiniciada', '0%  just reset', F.quotaDetail({pct: 0, resets_in: null, reset: true}));
eq('sem dados', 'no data yet', F.quotaDetail(null));

print(`\nResultado: ${pass} ok, ${fail} falha(s)`);
System.exit(fail ? 1 : 0);
