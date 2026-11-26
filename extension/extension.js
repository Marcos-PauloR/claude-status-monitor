// Claude Status Monitor — indicador no painel do GNOME Shell.
// Painel no estilo do system-monitor-next: rótulo pequeno em cima, valor embaixo (SPEC RF01).
// Menu: cotas da conta no topo, uma entrada por janela ativa (RF03, RF04, RF08, RF09).
// Cada coluna tem a própria cor, com limiares gerais ou do próprio indicador (T13).
// v1.3: uma seção do menu por conta, janela fixada (arquivo `pinned`) e temas de cores aplicados
// via `style` inline (as classes de nível do stylesheet ficam como reserva).

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

import {readConfig} from './config.js';
import {resolveLanguage, translator} from './i18n.js';
import {
    clearPinned, dataDir, formatDuration, formatTokens, readCompactEvents, readPinned, sessionsDir, summarize,
    writePinned,
} from './store.js';
import {loadTheme} from './themes.js';
import {SnapshotWatcher} from './watcher.js';

const LEVEL_CLASSES = ['', 'claude-status-warn', 'claude-status-crit'];
const BAR_WIDTH = 120;

// Estilo inline de cor; cor vazia no tema = segue o stylesheet/tema do Shell.
const colorStyle = color => (color ? `color: ${color};` : '');
const levelColor = (theme, lv) => [theme.normal, theme.warn, theme.crit][lv ?? 0];
// Nome da conta: cor `accent`, ou negrito quando o tema não define accent.
const accentStyle = theme => (theme.accent ? `color: ${theme.accent};` : 'font-weight: bold;');

// Barra de % com a cor do nível.
function makeBar(pct, level, theme) {
    const fillColor = level === 0 ? theme.bar : level === 1 ? theme.warn : theme.crit;
    const fill = new St.Widget({
        style_class: `claude-status-bar-fill ${LEVEL_CLASSES[level]}`,
        style: `width: ${Math.round(BAR_WIDTH * Math.min(Math.max(pct ?? 0, 0), 100) / 100)}px;` +
            (fillColor ? ` background-color: ${fillColor};` : ''),
    });
    const trough = new St.BoxLayout({
        style_class: 'claude-status-bar',
        style: `width: ${BAR_WIDTH}px;`,
        y_align: Clutter.ActorAlign.CENTER,
    });
    trough.add_child(fill);
    return trough;
}

function infoItem(child) {
    const item = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
    item.add_child(child);
    return item;
}

const pctText = pct => (pct === null || pct === undefined ? '—' : `${pct}%`);
const show = v => (v === null || v === undefined ? '—' : String(v));

// [chave, unidade]; o rótulo é a chave traduzida.
export const COLUMNS = [
    ['model', ''],
    ['ctx', '%'],
    ['session', '%'],
    ['resets', ''],
    ['compacts', ''],
    ['weekly', '%'],
];
// Nível (cor) de cada coluna: resets acompanha session; model e compacts não mudam de cor.
const COLUMN_LEVEL = {ctx: 'ctx', session: 'session', resets: 'session', weekly: 'weekly'};
// No modo `all`, essas colunas saem do bloco principal e vão para o grupo de cada conta.
const ACCOUNT_COLUMNS = ['session', 'resets', 'weekly'];

// thresholds-override (a{s(ii)}) -> {ctx: {warn, crit}, ...}
function overrides(settings) {
    const out = {};
    for (const [key, [warn, crit]] of Object.entries(settings.get_value('thresholds-override').deep_unpack()))
        out[key] = {warn, crit};
    return out;
}

const ClaudeStatusIndicator = GObject.registerClass(
class ClaudeStatusIndicator extends PanelMenu.Button {
    _init(extension, settings) {
        super._init(0.0, 'Claude Status', false);
        this._extension = extension;
        this._settings = settings;
        this._t = translator(resolveLanguage(settings.get_string('language')));
        this._theme = loadTheme(settings.get_string('theme'));
        this._snapshots = [];
        this._refreshId = 0;
        this._titles = [];
        this._units = {};

        this._box = new St.BoxLayout({style_class: 'claude-status-box'});
        this.add_child(this._box);

        this._empty = new St.Label({
            text: 'Claude —',
            style_class: 'claude-status-empty',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._box.add_child(this._empty);

        // Coluna da conta (modo focus com mais de uma conta), à esquerda das outras.
        const account = this._column(this._t('account'), '');
        this._accountColumn = account.column;
        this._accountValue = account.value;
        this._box.add_child(this._accountColumn);

        this._values = {};
        this._columnActors = {};
        this._columns = new St.BoxLayout({style_class: 'claude-status-columns'});
        for (const [key, unit] of COLUMNS) {
            const {column, value, unitLabel} = this._column(this._t(key), unit);
            this._values[key] = value;
            this._units[key] = unitLabel;
            this._columns.add_child(column);
            this._columnActors[key] = column;
        }
        this._box.add_child(this._columns);

        // Grupos por conta (modo all): recriados só quando a lista de contas muda.
        this._groupsBox = new St.BoxLayout({style_class: 'claude-status-columns'});
        this._box.add_child(this._groupsBox);
        this._groups = new Map();
        this._groupKey = '';

        this._buildMenu();
        this.connect('destroy', () => {
            if (this._refreshId)
                GLib.source_remove(this._refreshId);
            this._refreshId = 0;
        });
    }

    // Coluna do painel: rótulo pequeno em cima e valor (+ unidade) embaixo.
    _column(title, unit) {
        const column = new St.BoxLayout({
            orientation: Clutter.Orientation.VERTICAL,
            style_class: 'claude-status-column',
            y_align: Clutter.ActorAlign.CENTER,
        });
        const titleLabel = new St.Label({text: title, style_class: 'claude-status-title', x_align: Clutter.ActorAlign.CENTER});
        this._titles.push(titleLabel);
        column.add_child(titleLabel);

        const row = new St.BoxLayout({style_class: 'claude-status-row', x_align: Clutter.ActorAlign.CENTER});
        const value = new St.Label({style_class: 'claude-status-value'});
        row.add_child(value);
        let unitLabel = null;
        if (unit) {
            unitLabel = new St.Label({text: unit, style_class: 'claude-status-unit', y_align: Clutter.ActorAlign.END});
            row.add_child(unitLabel);
        }
        column.add_child(row);
        return {column, row, title: titleLabel, value, unitLabel};
    }

    _buildMenu() {
        this._accountsSection = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._accountsSection);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addAction(this._t('Open data folder'), () => {
            try {
                Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(dataDir()).get_uri(),
                    global.create_app_launch_context(0, -1));
            } catch (e) {
                console.warn(`claude-status: não foi possível abrir ${dataDir()}: ${e.message}`);
            }
        });
        this.menu.addAction(this._t('Preferences'), () => this._extension.openPreferences());

        // compacts.jsonl só é lido com o menu aberto (RF09): ao abrir, recalcula com os eventos.
        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this._refresh();
        });
    }

    // Recalcula com os últimos snapshots (fixar/desafixar, abrir o menu).
    _refresh() {
        this.update(this._snapshots);
    }

    // Fixar/desafixar sai do clique do item: o menu é reconstruído fora da emissão do sinal.
    _setPinned(id) {
        if (id)
            writePinned(id);
        else
            clearPinned();
        if (this._refreshId)
            return;
        this._refreshId = GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            this._refreshId = 0;
            this._refresh();
            return GLib.SOURCE_REMOVE;
        });
    }

    _labelStyle() {
        return colorStyle(this._theme.label);
    }

    _quotaRow(key, quota, level) {
        const row = new St.BoxLayout({style_class: 'claude-status-menu-row'});
        row.add_child(new St.Label({
            text: this._t(key), style_class: 'claude-status-menu-key', style: this._labelStyle(),
            y_align: Clutter.ActorAlign.CENTER,
        }));
        if (!quota) {
            row.add_child(new St.Label({text: this._t('no data yet'), style_class: 'claude-status-menu-detail', style: this._labelStyle()}));
            return row;
        }
        row.add_child(makeBar(quota.pct, level ?? 0, this._theme));
        row.add_child(new St.Label({
            text: pctText(quota.pct), style_class: 'claude-status-menu-pct',
            style: colorStyle(levelColor(this._theme, level)), y_align: Clutter.ActorAlign.CENTER,
        }));
        const when = quota.reset ? this._t('just reset') : `${this._t('resets in')} ${formatDuration(quota.resetsIn)}`;
        row.add_child(new St.Label({
            text: when, style_class: 'claude-status-menu-detail', style: this._labelStyle(), y_align: Clutter.ActorAlign.CENTER,
        }));
        return row;
    }

    _windowBox(w) {
        const box = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'claude-status-menu-window'});
        const title = [w.project ?? this._t('(no project)'), w.name].filter(Boolean).join(' — ');
        const titleRow = new St.BoxLayout({style_class: 'claude-status-menu-title-row'});
        if (w.pinned) {
            titleRow.add_child(new St.Icon({
                icon_name: 'view-pin-symbolic', style_class: 'claude-status-menu-pin',
                style: colorStyle(this._theme.accent), y_align: Clutter.ActorAlign.CENTER,
            }));
        }
        titleRow.add_child(new St.Label({text: title, style_class: 'claude-status-menu-title'}));
        box.add_child(titleRow);
        box.add_child(new St.Label({
            text: `${w.model ?? '—'} · ${this._t('compacts')} ${w.compacts}`,
            style_class: 'claude-status-menu-detail',
            style: this._labelStyle(),
        }));
        const row = new St.BoxLayout({style_class: 'claude-status-menu-row'});
        row.add_child(new St.Label({text: 'ctx', style_class: 'claude-status-menu-key', style: this._labelStyle(), y_align: Clutter.ActorAlign.CENTER}));
        row.add_child(makeBar(w.ctx, w.level, this._theme));
        row.add_child(new St.Label({
            text: pctText(w.ctx), style_class: 'claude-status-menu-pct',
            style: colorStyle(levelColor(this._theme, w.level)), y_align: Clutter.ActorAlign.CENTER,
        }));
        row.add_child(new St.Label({
            text: `${formatTokens(w.tokens)} / ${formatTokens(w.window)}`,
            style_class: 'claude-status-menu-detail',
            style: this._labelStyle(),
            y_align: Clutter.ActorAlign.CENTER,
        }));
        box.add_child(row);
        return box;
    }

    // Uma seção por conta: [cabeçalho, se houver mais de uma], cotas, compacts da semana, janelas.
    _updateMenu(s) {
        this._accountsSection.removeAll();
        if (!s) {
            this._accountsSection.addMenuItem(infoItem(new St.Label({text: this._t('no active windows')})));
            return;
        }
        s.accounts.forEach((a, i) => {
            const section = this._accountsSection;
            if (i > 0)
                section.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
            if (s.multi) {
                const header = new PopupMenu.PopupMenuItem(a.label, {reactive: false, can_focus: false});
                header.label.style = `font-weight: bold; ${colorStyle(this._theme.accent)}`;
                section.addMenuItem(header);
            }
            section.addMenuItem(infoItem(this._quotaRow('session', a.quotas.session, a.levels.session)));
            section.addMenuItem(infoItem(this._quotaRow('weekly', a.quotas.weekly, a.levels.weekly)));
            // Com o menu fechado não há eventos (a contagem é refeita ao abrir).
            section.addMenuItem(infoItem(new St.Label({
                text: `${this._t('compacts this week')}: ${a.weekCompacts}`,
                style_class: 'claude-status-menu-detail',
                style: this._labelStyle(),
            })));
            if (a.windows.length > 0)
                section.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
            for (const w of a.windows) {
                section.addMenuItem(infoItem(this._windowBox(w)));
                const pin = new PopupMenu.PopupImageMenuItem(w.pinned ? this._t('Unpin') : this._t('Pin to panel'),
                    'view-pin-symbolic');
                pin.label.style = this._labelStyle();
                pin.connect('activate', () => this._setPinned(w.pinned ? null : w.id));
                section.addMenuItem(pin);
            }
        });
    }

    // Ordem (panel-order, completada com o que faltar) e visibilidade das colunas.
    _layoutColumns(visible) {
        const order = this._settings.get_strv('panel-order').filter(k => k in this._columnActors);
        for (const [key] of COLUMNS) {
            if (!order.includes(key))
                order.push(key);
        }
        order.forEach((key, i) => this._columns.set_child_at_index(this._columnActors[key], i));
        for (const [key, column] of Object.entries(this._columnActors))
            column.visible = visible.includes(key);
        return order;
    }

    // Modo all: um grupo por conta com o apelido em cima e session/weekly lado a lado.
    _updateGroups(s, fields, order) {
        const accounts = s?.accounts ?? [];
        const key = accounts.map(a => a.id).join('\n');
        if (key !== this._groupKey) {
            this._groupsBox.destroy_all_children();
            this._groups.clear();
            this._groupKey = key;
            for (const a of accounts) {
                const column = new St.BoxLayout({
                    orientation: Clutter.Orientation.VERTICAL,
                    style_class: 'claude-status-column claude-status-group',
                    y_align: Clutter.ActorAlign.CENTER,
                });
                const title = new St.Label({style_class: 'claude-status-title', x_align: Clutter.ActorAlign.CENTER});
                column.add_child(title);
                const row = new St.BoxLayout({style_class: 'claude-status-row claude-status-group-row', x_align: Clutter.ActorAlign.CENTER});
                const cells = {};
                for (const k of ['session', 'weekly']) {
                    const cell = new St.BoxLayout({style_class: 'claude-status-group-cell'});
                    const value = new St.Label({style_class: 'claude-status-value'});
                    const unit = new St.Label({text: '%', style_class: 'claude-status-unit', y_align: Clutter.ActorAlign.END});
                    cell.add_child(value);
                    cell.add_child(unit);
                    row.add_child(cell);
                    cells[k] = {cell, value, unit};
                }
                column.add_child(row);
                this._groupsBox.add_child(column);
                this._groups.set(a.id, {column, row, title, cells});
            }
        }
        // session/weekly na ordem do painel; desligado em panel-fields some de todos os grupos.
        const keys = order.filter(k => k === 'session' || k === 'weekly');
        for (const a of accounts) {
            const g = this._groups.get(a.id);
            g.title.text = a.label;
            g.title.style = accentStyle(this._theme);
            keys.forEach((k, i) => g.row.set_child_at_index(g.cells[k].cell, i));
            for (const k of keys) {
                const c = g.cells[k];
                c.cell.visible = fields.includes(k);
                c.value.text = show(a[k]);
                const style = colorStyle(levelColor(this._theme, a.levels[k]));
                c.value.style = c.unit.style = style;
                for (const cls of LEVEL_CLASSES.filter(Boolean))
                    c.cell.remove_style_class_name(cls);
                if (a.levels[k])
                    c.cell.add_style_class_name(LEVEL_CLASSES[a.levels[k]]);
            }
            g.column.visible = keys.some(k => fields.includes(k));
        }
    }

    update(snapshots) {
        this._snapshots = [...snapshots];
        this._theme = loadTheme(this._settings.get_string('theme'));
        const pinned = readPinned();
        const {labels} = readConfig();
        const s = summarize(this._snapshots, Math.floor(Date.now() / 1000), {
            warn: this._settings.get_int('warn-threshold'),
            crit: this._settings.get_int('crit-threshold'),
            thresholds: overrides(this._settings),
            inactiveMinutes: this._settings.get_int('inactive-minutes'),
            pinned,
            labels,
            events: this.menu.isOpen ? readCompactEvents() : [],
        });
        // Fixada que sumiu ou ficou inativa é esquecida (spec §2.3).
        if (pinned && (!s || !s.pinnedValid))
            clearPinned();

        const all = this._settings.get_string('panel-accounts') === 'all';
        const fields = this._settings.get_strv('panel-fields');
        const mainFields = all ? fields.filter(k => !ACCOUNT_COLUMNS.includes(k)) : fields;
        const order = this._layoutColumns(mainFields);
        const levels = s?.levels ?? {};
        const shown = all ? mainFields.length + fields.filter(k => k === 'session' || k === 'weekly').length
            : fields.length;

        // Sem janelas: "Claude —". Com todos os campos desligados: só "Claude".
        this._empty.text = s ? 'Claude' : 'Claude —';
        this._empty.visible = !s || shown === 0;
        this._columns.visible = !!s && mainFields.length > 0;
        this._groupsBox.visible = !!s && all;
        this._accountColumn.visible = !!s && !all && s.multi && shown > 0;
        for (const label of this._titles)
            label.style = this._labelStyle();
        for (const [key, column] of Object.entries(this._columnActors)) {
            for (const cls of LEVEL_CLASSES.filter(Boolean))
                column.remove_style_class_name(cls);
            const lv = levels[COLUMN_LEVEL[key]];
            if (lv)
                column.add_style_class_name(LEVEL_CLASSES[lv]);
            const style = colorStyle(levelColor(this._theme, lv));
            this._values[key].style = style;
            if (this._units[key])
                this._units[key].style = style;
        }
        this._updateGroups(all ? s : null, fields, order);
        this._updateMenu(s);
        if (!s)
            return;

        this._accountValue.text = labels[s.focus.account] ?? s.focus.account;
        this._accountValue.style = accentStyle(this._theme);
        this._values.model.text = s.model;
        this._values.ctx.text = show(s.ctx);
        this._values.session.text = show(s.session);
        this._values.resets.text = formatDuration(s.sessionResets);
        this._values.compacts.text = show(s.compacts);
        this._values.weekly.text = show(s.weekly);
    }
});

export default class ClaudeStatusExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._watcher = new SnapshotWatcher(sessionsDir(), snapshots => this._indicator?.update(snapshots));
        // O watcher lê os snapshots antes de o indicador nascer: com o cache ainda vazio, o
        // indicador acharia a janela fixada inativa e apagaria o `pinned`.
        this._watcher.start();
        this._addIndicator();
        this._settingsId = this._settings.connect('changed', (_settings, key) => {
            // Posição e idioma exigem recriar o botão (rótulos e posição são definidos na criação).
            if (key === 'panel-box' || key === 'panel-index' || key === 'language')
                this._addIndicator();
            else
                this._indicator?.update(this._watcher.snapshots);
        });
    }

    // Mudar a posição exige recriar o botão: addToStatusArea só posiciona na criação.
    _addIndicator() {
        this._indicator?.destroy();
        this._indicator = new ClaudeStatusIndicator(this, this._settings);
        Main.panel.addToStatusArea(this.uuid, this._indicator,
            this._settings.get_int('panel-index'), this._settings.get_string('panel-box'));
        this._indicator.update(this._watcher.snapshots);
    }

    disable() {
        if (this._settingsId)
            this._settings.disconnect(this._settingsId);
        this._settingsId = 0;
        this._settings = null;
        this._watcher?.stop();
        this._watcher = null;
        this._indicator?.destroy();
        this._indicator = null;
    }
}
