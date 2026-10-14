// Claude Status Monitor — indicador no painel do GNOME Shell.
// Painel no estilo do system-monitor-next: rótulo pequeno em cima, valor embaixo (SPEC RF01).
// Menu: cotas da conta no topo, uma entrada por janela ativa (RF03, RF04, RF08, RF09).

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

import {
    countSince, dataDir, formatDuration, formatTokens, level, readCompacts, sessionsDir, summarize,
} from './store.js';
import {SnapshotWatcher} from './watcher.js';

const LEVEL_CLASSES = ['', 'claude-status-warn', 'claude-status-crit'];
const BAR_WIDTH = 120;

// Barra de % com a cor do nível.
function makeBar(pct, level) {
    const fill = new St.Widget({
        style_class: `claude-status-bar-fill ${LEVEL_CLASSES[level]}`,
        style: `width: ${Math.round(BAR_WIDTH * Math.min(Math.max(pct ?? 0, 0), 100) / 100)}px;`,
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

// [chave, rótulo, unidade]
const COLUMNS = [
    ['model', 'model', ''],
    ['ctx', 'ctx', '%'],
    ['session', 'session', '%'],
    ['resets', 'resets', ''],
    ['compacts', 'compacts', ''],
    ['weekly', 'weekly', '%'],
];

const ClaudeStatusIndicator = GObject.registerClass(
class ClaudeStatusIndicator extends PanelMenu.Button {
    _init(extension, settings) {
        super._init(0.0, 'Claude Status', false);
        this._extension = extension;
        this._settings = settings;
        this._weekStart = null;

        this._box = new St.BoxLayout({style_class: 'claude-status-box'});
        this.add_child(this._box);

        this._empty = new St.Label({
            text: 'Claude —',
            style_class: 'claude-status-empty',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._box.add_child(this._empty);

        this._values = {};
        this._columnActors = {};
        this._columns = new St.BoxLayout({style_class: 'claude-status-columns'});
        for (const [key, title, unit] of COLUMNS) {
            const column = new St.BoxLayout({
                orientation: Clutter.Orientation.VERTICAL,
                style_class: 'claude-status-column',
                y_align: Clutter.ActorAlign.CENTER,
            });
            column.add_child(new St.Label({
                text: title,
                style_class: 'claude-status-title',
                x_align: Clutter.ActorAlign.CENTER,
            }));

            const row = new St.BoxLayout({style_class: 'claude-status-row', x_align: Clutter.ActorAlign.CENTER});
            this._values[key] = new St.Label({style_class: 'claude-status-value'});
            row.add_child(this._values[key]);
            if (unit)
                row.add_child(new St.Label({text: unit, style_class: 'claude-status-unit', y_align: Clutter.ActorAlign.END}));
            column.add_child(row);
            this._columns.add_child(column);
            this._columnActors[key] = column;
        }
        this._box.add_child(this._columns);

        this._buildMenu();
    }

    _buildMenu() {
        this._quotaSection = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._quotaSection);

        this._weekCompacts = new St.Label({style_class: 'claude-status-menu-detail'});
        this._weekCompactsItem = infoItem(this._weekCompacts);
        this.menu.addMenuItem(this._weekCompactsItem);

        this._quotaSeparator = new PopupMenu.PopupSeparatorMenuItem();
        this.menu.addMenuItem(this._quotaSeparator);

        this._windowsSection = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._windowsSection);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addAction('Open data folder', () => {
            try {
                Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(dataDir()).get_uri(),
                    global.create_app_launch_context(0, -1));
            } catch (e) {
                console.warn(`claude-status: não foi possível abrir ${dataDir()}: ${e.message}`);
            }
        });
        this.menu.addAction('Preferences', () => this._extension.openPreferences());

        // compacts.jsonl só é lido quando o menu abre (RF09).
        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this._updateWeekCompacts();
        });
    }

    _updateWeekCompacts() {
        if (this._weekStart === null)
            return;
        this._weekCompacts.text = `compacts this week: ${countSince(readCompacts(), this._weekStart)}`;
    }

    _quotaRow(title, quota) {
        const row = new St.BoxLayout({style_class: 'claude-status-menu-row'});
        row.add_child(new St.Label({text: title, style_class: 'claude-status-menu-key', y_align: Clutter.ActorAlign.CENTER}));
        if (!quota) {
            row.add_child(new St.Label({text: 'no data yet', style_class: 'claude-status-menu-detail'}));
            return row;
        }
        row.add_child(makeBar(quota.pct, level(quota.pct, this._thresholds())));
        row.add_child(new St.Label({text: pctText(quota.pct), style_class: 'claude-status-menu-pct', y_align: Clutter.ActorAlign.CENTER}));
        const when = quota.reset ? 'just reset' : `resets in ${formatDuration(quota.resetsIn)}`;
        row.add_child(new St.Label({text: when, style_class: 'claude-status-menu-detail', y_align: Clutter.ActorAlign.CENTER}));
        return row;
    }

    _windowBox(w) {
        const box = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, style_class: 'claude-status-menu-window'});
        const title = [w.project ?? '(no project)', w.name].filter(Boolean).join(' — ');
        box.add_child(new St.Label({text: title, style_class: 'claude-status-menu-title'}));
        box.add_child(new St.Label({
            text: `${w.model ?? '—'} · compacts ${w.compacts}`,
            style_class: 'claude-status-menu-detail',
        }));
        const row = new St.BoxLayout({style_class: 'claude-status-menu-row'});
        row.add_child(new St.Label({text: 'ctx', style_class: 'claude-status-menu-key', y_align: Clutter.ActorAlign.CENTER}));
        row.add_child(makeBar(w.ctx, w.level));
        row.add_child(new St.Label({text: pctText(w.ctx), style_class: 'claude-status-menu-pct', y_align: Clutter.ActorAlign.CENTER}));
        row.add_child(new St.Label({
            text: `${formatTokens(w.tokens)} / ${formatTokens(w.window)}`,
            style_class: 'claude-status-menu-detail',
            y_align: Clutter.ActorAlign.CENTER,
        }));
        box.add_child(row);
        return box;
    }

    _updateMenu(s) {
        this._quotaSection.removeAll();
        this._windowsSection.removeAll();
        this._quotaSeparator.visible = this._weekCompactsItem.visible = !!s;
        this._weekStart = s?.weekStart ?? null;

        if (!s) {
            this._windowsSection.addMenuItem(infoItem(new St.Label({text: 'no active windows'})));
            return;
        }
        this._quotaSection.addMenuItem(infoItem(this._quotaRow('session', s.quotas.session)));
        this._quotaSection.addMenuItem(infoItem(this._quotaRow('weekly', s.quotas.weekly)));
        if (this.menu.isOpen)
            this._updateWeekCompacts();
        for (const w of s.windows)
            this._windowsSection.addMenuItem(infoItem(this._windowBox(w)));
    }

    _thresholds() {
        return {warn: this._settings.get_int('warn-threshold'), crit: this._settings.get_int('crit-threshold')};
    }

    update(snapshots) {
        const s = summarize(snapshots, Math.floor(Date.now() / 1000), {
            ...this._thresholds(),
            inactiveMinutes: this._settings.get_int('inactive-minutes'),
        });
        const fields = this._settings.get_strv('panel-fields');
        for (const [key, column] of Object.entries(this._columnActors))
            column.visible = fields.includes(key);

        // Sem janelas: "Claude —". Com todos os campos desligados: só "Claude".
        this._empty.text = s ? 'Claude' : 'Claude —';
        this._empty.visible = !s || fields.length === 0;
        this._columns.visible = !!s && fields.length > 0;
        for (const cls of LEVEL_CLASSES.filter(Boolean))
            this._box.remove_style_class_name(cls);
        this._updateMenu(s);
        if (!s)
            return;

        const show = v => (v === null || v === undefined ? '—' : String(v));
        this._values.model.text = s.model;
        this._values.ctx.text = show(s.ctx);
        this._values.session.text = show(s.session);
        this._values.resets.text = formatDuration(s.sessionResets);
        this._values.compacts.text = show(s.compacts);
        this._values.weekly.text = show(s.weekly);
        if (s.level)
            this._box.add_style_class_name(LEVEL_CLASSES[s.level]);
    }
});

export default class ClaudeStatusExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._watcher = new SnapshotWatcher(sessionsDir(), snapshots => this._indicator?.update(snapshots));
        this._addIndicator();
        this._settingsId = this._settings.connect('changed', (_settings, key) => {
            if (key === 'panel-box' || key === 'panel-index')
                this._addIndicator();
            else
                this._indicator?.update(this._watcher.snapshots);
        });
        this._watcher.start();
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
