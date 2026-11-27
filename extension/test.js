// Testes da lógica da extensão (fora do GNOME Shell). Uso: gjs -m extension/test.js
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import System from 'system';

import {
    accountOf, countSince, formatDuration, formatTokens, isSnapshotName, level, parseCompactEvents, parseCompacts,
    parseSnapshot, summarize, weekStart,
} from './store.js';
import {SnapshotWatcher} from './watcher.js';
import {parseConfig} from './config.js';
import {DEFAULT_THEME, isColor, listThemes, loadTheme, parseTheme} from './themes.js';
import {PT_KEYS, resolveLanguage, translator} from './i18n.js';

let pass = 0, fail = 0;
function eq(desc, expected, actual) {
    const e = JSON.stringify(expected), a = JSON.stringify(actual);
    if (e === a) {
        pass++;
        print(`  ok   ${desc}`);
    } else {
        fail++;
        print(`  FAIL ${desc}\n       esperado: ${e} obtido: ${a}`);
    }
}
const throws = fn => { try { fn(); return false; } catch { return true; } };

const NOW = 1760450000;
const snap = (id, ago, extra = {}) => ({
    schema: 1, session_id: id, updated_at: NOW - ago, model: 'Opus 5.5',
    context: {used_pct: 10, window: 200000, tokens: 20000}, compacts: 0, limits: null, ...extra,
});
const limits = (s, w, sReset = NOW + 4320, wReset = NOW + 86400 * 3) =>
    ({five_hour: {used_pct: s, resets_at: sReset}, seven_day: {used_pct: w, resets_at: wReset}});

print('== formatDuration');
eq('minutos', '45m', formatDuration(45 * 60 + 59));
eq('horas', '1h12', formatDuration(4320));
eq('horas com zero', '2h05', formatDuration(2 * 3600 + 5 * 60));
eq('dias', '3d4h', formatDuration(3 * 86400 + 4 * 3600 + 120));
eq('nulo', '—', formatDuration(null));

print('== level (RF02)');
eq('normal', 0, level(69));
eq('aviso', 1, level(70));
eq('aviso alto', 1, level(89));
eq('crítico', 2, level(90));
eq('nulo', 0, level(null));

print('== isSnapshotName / parseSnapshot');
eq('json', true, isSnapshotName('abc.json'));
eq('temporário', false, isSnapshotName('.abc.json.Xy12ab'));
eq('outro', false, isSnapshotName('abc.txt'));
eq('json inválido lança', true, throws(() => parseSnapshot('{ quebrado')));
eq('schema errado lança', true, throws(() => parseSnapshot('{"schema":2,"session_id":"a","updated_at":1}')));
eq('válido', 'a', parseSnapshot('{"schema":1,"session_id":"a","updated_at":1}').session_id);

print('== summarize');
eq('sem snapshots: null (RF06)', null, summarize([], NOW));
eq('só inativos: null (RF05)', null, summarize([snap('a', 16 * 60)], NOW));

let s = summarize([
    snap('old', 300, {model: 'Sonnet 5.5', limits: limits(40, 20)}),
    snap('new', 10, {context: {used_pct: 42}, compacts: 2}),
], NOW);
eq('model/ctx/compacts da janela mais recente', ['Opus 5.5', 42, 2], [s.model, s.ctx, s.compacts]);
eq('cota do snapshot mais recente com limits (RF07)', [40, 4320 - 0, 20], [s.session, s.sessionResets, s.weekly]);
eq('lista de ativas ordenada', ['new', 'old'], s.active.map(x => x.session_id));

s = summarize([snap('a', 10, {limits: limits(50, 10)}), snap('b', 60, {limits: limits(99, 99)})], NOW);
eq('cota vem do mais recente mesmo se menor', 50, s.session);

s = summarize([snap('a', 10), snap('gone', 3600, {limits: limits(33, 11)})], NOW);
eq('cota de janela inativa ainda vale', [33, 11], [s.session, s.weekly]);

s = summarize([snap('a', 10, {limits: limits(80, 30, NOW - 1)})], NOW);
eq('reset já passou: 0% e sem contagem (RF07)', [0, null, 30], [s.session, s.sessionResets, s.weekly]);

eq('nível = pior indicador', 1, summarize([snap('a', 1, {limits: limits(75, 10)})], NOW).level);
eq('ctx crítico', 2, summarize([snap('a', 1, {context: {used_pct: 95}})], NOW).level);
eq('ctx nulo', [null, 0], (x => [x.ctx, x.level])(summarize([snap('a', 1, {context: {used_pct: null}})], NOW)));
eq('limits nulo', [null, null], (x => [x.session, x.weekly])(summarize([snap('a', 1)], NOW)));

print('== formatTokens');
eq('mil', '55k', formatTokens(54820));
eq('milhão', '1M', formatTokens(1000000));
eq('milhão fracionado', '1.5M', formatTokens(1500000));
eq('pequeno', '900', formatTokens(900));
eq('nulo', '—', formatTokens(null));

print('== compacts da semana (RF09)');
eq('parse ignora linha inválida', [10, 30], parseCompacts('{"ts":10,"session_id":"a"}\nlixo\n\n{"ts":30}\n{"x":1}\n'));
eq('início da semana pelo seven_day', NOW + 3600 - 7 * 86400, weekStart(limits(1, 1, NOW, NOW + 3600), NOW));
eq('sem limits: últimos 7 dias', NOW - 7 * 86400, weekStart(null, NOW));
eq('reset semanal já passou: semana começa no reset', NOW - 60, weekStart(limits(1, 1, NOW, NOW - 60), NOW));
eq('conta desde o início', 2, countSince([NOW - 8 * 86400, NOW - 86400, NOW], NOW - 7 * 86400));

print('== summarize: menu (RF03, RF04, RF07)');
s = summarize([
    snap('a', 10, {project: 'my-app', session_name: 'core', context: {used_pct: 75, window: 1000000, tokens: 750000},
        compacts: 3, limits: limits(40, 20)}),
    snap('b', 60, {project: 'outro'}),
], NOW);
eq('janelas na ordem', ['a', 'b'], s.windows.map(w => w.id));
eq('dados da janela', {id: 'a', account: 'default', pinned: false, project: 'my-app', name: 'core', model: 'Opus 5.5', ctx: 75, tokens: 750000,
    window: 1000000, compacts: 3, level: 1}, s.windows[0]);
eq('cota session com reset', {pct: 40, resetsIn: 4320, reset: false}, s.quotas.session);
eq('cota weekly com reset', {pct: 20, resetsIn: 86400 * 3, reset: false}, s.quotas.weekly);
eq('weekStart vem dos limits', NOW + 86400 * 3 - 7 * 86400, s.weekStart);
s = summarize([snap('a', 10, {limits: limits(80, 30, NOW - 1)})], NOW);
eq('reset passou: janela reiniciada', {pct: 0, resetsIn: null, reset: true}, s.quotas.session);
eq('sem limits: quotas nulas', [null, null], (x => [x.quotas.session, x.quotas.weekly])(summarize([snap('a', 1)], NOW)));

print('== summarize: opções (T5)');
s = summarize([snap('a', 10, {context: {used_pct: 55}, limits: limits(10, 10)})], NOW, {warn: 50, crit: 60});
eq('limiar de aviso configurável', [1, 1], [s.level, s.windows[0].level]);
s = summarize([snap('a', 10, {context: {used_pct: 65}, limits: limits(10, 10)})], NOW, {warn: 50, crit: 60});
eq('limiar crítico configurável', 2, s.level);
eq('inatividade configurável', null, summarize([snap('a', 120)], NOW, {inactiveMinutes: 1}));
eq('inatividade configurável (ativa)', 1, summarize([snap('a', 120)], NOW, {inactiveMinutes: 3}).windows.length);

print('== limiares por indicador (T13)');
s = summarize([snap('a', 10, {context: {used_pct: 60}, limits: limits(60, 60)})], NOW,
    {thresholds: {ctx: {warn: 50, crit: 80}, weekly: {warn: 40, crit: 55}}});
eq('níveis por indicador', {ctx: 1, session: 0, weekly: 2}, s.levels);
eq('nível geral = pior', 2, s.level);
eq('janela usa o limiar do ctx', 1, s.windows[0].level);
s = summarize([snap('a', 10, {context: {used_pct: 60}, limits: limits(60, 60)})], NOW,
    {warn: 55, crit: 90, thresholds: {session: {warn: 70, crit: 95}}});
eq('sem override usa o geral; com override usa o próprio', {ctx: 1, session: 0, weekly: 1}, s.levels);
eq('sem limits: níveis 0', {ctx: 0, session: 0, weekly: 0}, summarize([snap('a', 1)], NOW).levels);

print('== contas (v1.3)');
{
    const snaps = [
        snap('d1', 10, {context: {used_pct: 42}, limits: limits(31, 12)}),
        snap('w1', 20, {account: 'work', model: 'Sonnet 5.5', limits: limits(78, 40)}),
        snap('w2', 30, {account: 'work'}),
    ];
    const events = [{ts: NOW, account: 'default'}, {ts: NOW, account: 'work'}, {ts: NOW, account: 'work'}];
    const s = summarize(snaps, NOW, {events, labels: {work: 'Trabalho'}});
    eq('contas: default primeiro', ['default', 'work'], s.accounts.map(a => a.id));
    eq('apelido', ['default', 'Trabalho'], s.accounts.map(a => a.label));
    eq('cota por conta', [[31, 12], [78, 40]], s.accounts.map(a => [a.session, a.weekly]));
    eq('janelas por conta', [['d1'], ['w1', 'w2']], s.accounts.map(a => a.windows.map(w => w.id)));
    eq('compacts da semana por conta', [1, 2], s.accounts.map(a => a.weekCompacts));
    eq('topo = janela em foco e sua conta', ['d1', 42, 31, 12], [s.focus.id, s.ctx, s.session, s.weekly]);
    eq('multi', true, s.multi);
}
eq('accountOf sem campo', 'default', accountOf({}));
eq('accountOf saneia', 'w_rk', accountOf({account: 'w/rk'}));
eq('parseCompactEvents', [{ts: 1, account: 'default'}, {ts: 2, account: 'work'}],
    parseCompactEvents('{"ts":1}\n{"ts":2,"account":"work"}\nlixo\n'));
{
    const snaps = [snap('d1', 10), snap('wold', 3600, {account: 'work', limits: limits(50, 50, NOW - 1, NOW - 1)})];
    eq('conta sem janela e com cota resetada some', ['default'], summarize(snaps, NOW).accounts.map(a => a.id));
    const snaps2 = [snap('d1', 10), snap('wold', 3600, {account: 'work', limits: limits(50, 50)})];
    eq('conta sem janela mas com cota aparece', [1, 0], summarize(snaps2, NOW).accounts.map(a => a.windows.length));
    const stale = {five_hour: {used_pct: 50}, seven_day: {used_pct: 50}};
    const snaps3 = [snap('d1', 10), snap('wold', 8 * 86400, {account: 'work', limits: stale})];
    eq('conta sem janela, sem resets_at e parada há > 7 d some', ['default'], summarize(snaps3, NOW).accounts.map(a => a.id));
    const snaps4 = [snap('d1', 10), snap('wold', 6 * 86400, {account: 'work', limits: stale})];
    eq('conta sem janela, sem resets_at e parada há < 7 d aparece', ['default', 'work'], summarize(snaps4, NOW).accounts.map(a => a.id));
}

print('== janela fixada (v1.3)');
{
    const snaps = [snap('a', 10, {context: {used_pct: 42}}), snap('b', 20, {context: {used_pct: 7}})];
    const s = summarize(snaps, NOW, {pinned: 'b'});
    eq('foco = fixada', ['b', 7, true], [s.focus.id, s.ctx, s.pinnedValid]);
    eq('janela fixada marcada', [false, true], s.windows.map(w => w.pinned));
    eq('órfã: foco = mais recente e inválida', ['a', false], (r => [r.focus.id, r.pinnedValid])(summarize(snaps, NOW, {pinned: 'sumiu'})));
    eq('sem fixação: pinnedValid true', true, summarize(snaps, NOW).pinnedValid);
}

print('== config e temas (v1.3)');
eq('apelidos do config', {labels: {work: 'Trabalho', 'w_x': 'X'}},
    parseConfig('# c\naccount.work = Trabalho\naccount.w/x=X\naccount.vazio=\nwarn=70\n'));
eq('isColor', [true, true, false, false], ['#abc', '#a1b2c3', 'amarelo', '#12345'].map(isColor));
{
    const {theme, errors} = parseTheme('ruim', 'name=Ruim\nwarn=amarelo\ncrit=#123\n');
    eq('tema parcial: chave ausente/inválida vem do default', ['Ruim', DEFAULT_THEME.warn, '#123', DEFAULT_THEME.bar],
        [theme.name, theme.warn, theme.crit, theme.bar]);
    eq('tema: erro registrado', 1, errors.length);
}
{
    const tmp = GLib.dir_make_tmp('cs-themes-XXXXXX');
    const user = GLib.build_filenamev([tmp, 'user']), data = GLib.build_filenamev([tmp, 'data']);
    GLib.mkdir_with_parents(user, 0o755);
    GLib.mkdir_with_parents(data, 0o755);
    GLib.file_set_contents(GLib.build_filenamev([data, 'nord.theme']), 'name=Nord\nwarn=#ebcb8b\n');
    GLib.file_set_contents(GLib.build_filenamev([user, 'nord.theme']), 'name=Meu Nord\n');
    GLib.file_set_contents(GLib.build_filenamev([user, 'meu.theme']), 'name=Meu\n');
    eq('o da pessoa vence', ['Meu Nord', DEFAULT_THEME.warn], (t => [t.name, t.warn])(loadTheme('nord', [user, data])));
    eq('inexistente: default', 'default', loadTheme('naoexiste', [user, data]).id);
    eq('lista: default primeiro, sem repetir', ['default', 'meu', 'nord'], listThemes([user, data]).map(t => t.id));
    GLib.spawn_command_line_sync(`rm -rf ${tmp}`);
}

print('== i18n (T13)');
eq('auto com pt_BR', 'pt', resolveLanguage('auto', ['pt_BR.UTF-8', 'pt_BR', 'pt', 'C']));
eq('auto com en_US', 'en', resolveLanguage('auto', ['en_US.UTF-8', 'en_US', 'en', 'C']));
eq('auto com C', 'en', resolveLanguage('auto', ['C']));
eq('forçado', ['en', 'pt'], [resolveLanguage('en', ['pt_BR']), resolveLanguage('pt', ['C'])]);
const tPt = translator('pt'), tEn = translator('en');
eq('traduz', ['sessão', 'Abrir pasta de dados'], [tPt('session'), tPt('Open data folder')]);
eq('inglês devolve a chave', 'session', tEn('session'));
eq('chave sem tradução devolve a chave', 'ctx', tPt('ctx'));

print('== i18n: todo texto da UI tem tradução');
{
    const dir = GLib.path_get_dirname(import.meta.url.replace('file://', ''));
    const read = f => new TextDecoder().decode(GLib.file_get_contents(GLib.build_filenamev([dir, f]))[1]);
    const used = new Set();
    for (const f of ['extension.js', 'prefs.js']) {
        for (const m of read(f).matchAll(/(?:^|[^\w])_?t\('([^']+)'\)/g))
            used.add(m[1]);
        for (const m of read(f).matchAll(/\b(?:desc|note): '([^']+)'/g))
            used.add(m[1]);
    }
    for (const m of read('extension.js').matchAll(/^\s+\['(\w+)', '%?'\],$/gm))
        used.add(m[1]);
    const untranslated = [...used].filter(k => !PT_KEYS.includes(k) && k !== 'ctx');
    eq(`${used.size} textos usados, todos traduzidos`, [], untranslated);
}

print('== SnapshotWatcher (diretório real temporário)');
const root = GLib.dir_make_tmp('claude-status-XXXXXX');
const dir = GLib.build_filenamev([root, 'sessions']);
const write = (name, text) => GLib.file_set_contents(GLib.build_filenamev([dir, name]), text);
const live = (id, ago = 0) => JSON.stringify(snap(id, ago, {updated_at: Math.floor(Date.now() / 1000) - ago}));

const loop = GLib.MainLoop.new(null, false);
const wait = ms => {
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => { loop.quit(); return GLib.SOURCE_REMOVE; });
    loop.run();
};
const sh = cmd => GLib.spawn_command_line_sync(`sh -c '${cmd}'`);

let emitted = 0;
const watcher = new SnapshotWatcher(dir, () => emitted++);
watcher.start();
const ids = () => [...watcher.snapshots].map(x => x.session_id).sort();
eq('cria o diretório', true, GLib.file_test(dir, GLib.FileTest.IS_DIR));
eq('começa vazio', [], ids());

write('.a.json.tmp123', live('a'));
sh(`mv ${dir}/.a.json.tmp123 ${dir}/a.json`);
wait(400);
eq('escrita atômica (rename) é lida', ['a'], ids());

write('b.json', live('b'));
write('broken.json', '{ quebrado');
write('.tmp-ignorado', live('x'));
wait(400);
eq('escrita direta lida; inválido e temporário ignorados', ['a', 'b'], ids());

sh(`rm ${dir}/a.json`);
wait(400);
eq('remoção (SessionEnd) some do cache', ['b'], ids());

sh(`rm -rf ${root}`);
wait(400);
eq('apagar o cache: recria o diretório', true, GLib.file_test(dir, GLib.FileTest.IS_DIR));
eq('apagar o cache: estado vazio', [], ids());
write('c.json', live('c'));
wait(400);
eq('continua monitorando após recriar', ['c'], ids());

const before = emitted;
watcher.stop();
write('d.json', live('d'));
wait(300);
eq('stop(): sem callbacks e cache limpo', [before, []], [emitted, ids()]);
sh(`rm -rf ${root}`);

print(`\nResultado: ${pass} ok, ${fail} falha(s)`);
System.exit(fail ? 1 : 0);
