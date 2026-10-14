// Claude Status Monitor — preferências (Adw), no estilo do system-monitor-next:
// General (limiares gerais, idioma, inatividade, posição), Indicators (ordem por arrastar,
// liga/desliga e limiares próprios por indicador) e About.

import Adw from 'gi://Adw';
import Gdk from 'gi://Gdk';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

import {resolveLanguage, translator} from './i18n.js';

// Indicadores do painel: descrição e se têm limiares de cor próprios.
const INDICATORS = {
    model: {desc: 'Model of the most recent window'},
    ctx: {desc: 'Context used by the most recent window', thresholds: true},
    session: {desc: 'Account usage in the current 5-hour session', thresholds: true},
    resets: {desc: 'Time until the session usage resets', note: 'Color follows the session indicator'},
    compacts: {desc: 'Compacts in the most recent window'},
    weekly: {desc: 'Account usage in the current week', thresholds: true},
};
const KEYS = Object.keys(INDICATORS);
const BOXES = ['left', 'center', 'right'];
const LANGUAGES = ['auto', 'en', 'pt'];
const REPO = 'https://github.com/Marcos-PauloR/claude-status-monitor';

function spinRow(title, subtitle, lower, upper, value) {
    return new Adw.SpinRow({
        title,
        subtitle: subtitle ?? '',
        adjustment: new Gtk.Adjustment({lower, upper, step_increment: 1, page_increment: 10, value}),
    });
}

function openUri(window, uri) {
    new Gtk.UriLauncher({uri}).launch(window, null, null);
}

export default class ClaudeStatusPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        window.set_default_size(640, 760);
        // Ícone próprio (icons/claude-status-symbolic.svg), sem depender do tema.
        Gtk.IconTheme.get_for_display(Gdk.Display.get_default()).add_search_path(`${this.path}/icons`);

        // Sinais ligados nesta janela; desligados ao reconstruir (troca de idioma) e ao fechar.
        let ids = [];
        const watch = (key, fn) => ids.push(settings.connect(`changed::${key}`, fn));
        const disconnectAll = () => {
            ids.forEach(id => settings.disconnect(id));
            ids = [];
        };
        let pages = [];

        const build = () => {
            disconnectAll();
            pages.forEach(p => window.remove(p));
            const t = translator(resolveLanguage(settings.get_string('language')));
            pages = [
                this._generalPage(settings, t, watch),
                this._indicatorsPage(settings, t, watch),
                this._aboutPage(window, t),
            ];
            pages.forEach(p => window.add(p));
            // O idioma muda os textos de todas as abas: reconstrói a janela.
            watch('language', () => GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
                build();
                window.set_visible_page(pages[0]);
                return GLib.SOURCE_REMOVE;
            }));
        };
        build();
        window.connect('close-request', () => {
            disconnectAll();
            return false;
        });
    }

    // ------------------------------------------------------------------ General

    _generalPage(settings, t, watch) {
        const page = new Adw.PreferencesPage({title: t('General'), icon_name: 'preferences-system-symbolic'});

        const colors = new Adw.PreferencesGroup({
            title: t('Colors'),
            description: t('Applies to every indicator that does not use its own thresholds.'),
        });
        const warn = spinRow(t('Yellow from (%)'), null, 1, 100, settings.get_int('warn-threshold'));
        const crit = spinRow(t('Red from (%)'), null, 1, 100, settings.get_int('crit-threshold'));
        settings.bind('warn-threshold', warn, 'value', Gio.SettingsBindFlags.DEFAULT);
        settings.bind('crit-threshold', crit, 'value', Gio.SettingsBindFlags.DEFAULT);
        // Vermelho nunca fica abaixo do amarelo.
        watch('warn-threshold', () => {
            if (settings.get_int('crit-threshold') < settings.get_int('warn-threshold'))
                settings.set_int('crit-threshold', settings.get_int('warn-threshold'));
        });
        watch('crit-threshold', () => {
            if (settings.get_int('warn-threshold') > settings.get_int('crit-threshold'))
                settings.set_int('warn-threshold', settings.get_int('crit-threshold'));
        });
        colors.add(warn);
        colors.add(crit);
        page.add(colors);

        const language = new Adw.PreferencesGroup({title: t('Language')});
        const lang = new Adw.ComboRow({
            title: t('Language'),
            model: Gtk.StringList.new([t('Automatic (system)'), 'English', 'Português']),
            selected: Math.max(0, LANGUAGES.indexOf(settings.get_string('language'))),
        });
        lang.connect('notify::selected', () => {
            const value = LANGUAGES[lang.selected];
            if (value && value !== settings.get_string('language'))
                settings.set_string('language', value);
        });
        language.add(lang);
        page.add(language);

        const windows = new Adw.PreferencesGroup({title: t('Windows')});
        const inactive = spinRow(t('Hide after (minutes)'),
            t('A Claude Code window without updates for this long disappears'), 1, 1440,
            settings.get_int('inactive-minutes'));
        settings.bind('inactive-minutes', inactive, 'value', Gio.SettingsBindFlags.DEFAULT);
        windows.add(inactive);
        page.add(windows);

        const position = new Adw.PreferencesGroup({title: t('Panel position')});
        const box = new Adw.ComboRow({
            title: t('Area'),
            model: Gtk.StringList.new([t('Left'), t('Center'), t('Right')]),
            selected: Math.max(0, BOXES.indexOf(settings.get_string('panel-box'))),
        });
        box.connect('notify::selected', () => {
            const value = BOXES[box.selected];
            if (value && value !== settings.get_string('panel-box'))
                settings.set_string('panel-box', value);
        });
        watch('panel-box', () => (box.selected = Math.max(0, BOXES.indexOf(settings.get_string('panel-box')))));
        const index = spinRow(t('Order'), t('Position inside the area (0 = first)'), 0, 20,
            settings.get_int('panel-index'));
        settings.bind('panel-index', index, 'value', Gio.SettingsBindFlags.DEFAULT);
        position.add(box);
        position.add(index);
        page.add(position);

        return page;
    }

    // ------------------------------------------------------------------ Indicators

    _indicatorsPage(settings, t, watch) {
        const page = new Adw.PreferencesPage({title: t('Indicators'), icon_name: 'view-list-symbolic'});
        const group = new Adw.PreferencesGroup({
            title: t('Panel indicators'),
            description: t('Drag to reorder. Changes apply immediately.'),
        });
        page.add(group);

        let rows = [];
        const order = () => {
            const o = settings.get_strv('panel-order').filter(k => KEYS.includes(k));
            return [...o, ...KEYS.filter(k => !o.includes(k))];
        };
        const fill = () => {
            rows.forEach(r => group.remove(r));
            rows = order().map(key => this._indicatorRow(settings, t, key, order));
            rows.forEach(r => group.add(r));
        };
        fill();
        watch('panel-order', fill);
        return page;
    }

    _indicatorRow(settings, t, key, order) {
        const info = INDICATORS[key];
        const row = info.thresholds
            ? new Adw.ExpanderRow({title: t(key), subtitle: t(info.desc)})
            : new Adw.ActionRow({title: t(key), subtitle: t(info.desc)});

        // Alça de arrastar (prefixo) + liga/desliga no painel (sufixo).
        const handle = new Gtk.Image({icon_name: 'list-drag-handle-symbolic', css_classes: ['dim-label']});
        row.add_prefix(handle);
        const toggle = new Gtk.Switch({
            valign: Gtk.Align.CENTER,
            active: settings.get_strv('panel-fields').includes(key),
            tooltip_text: t('Show in panel'),
        });
        toggle.connect('notify::active', () => {
            const current = settings.get_strv('panel-fields');
            if (toggle.active === current.includes(key))
                return;
            // Mantém a ordem do painel.
            settings.set_strv('panel-fields', order().filter(k => (k === key ? toggle.active : current.includes(k))));
        });
        row.add_suffix(toggle);

        this._dragAndDrop(settings, row, handle, key, order);

        if (info.note)
            row.set_subtitle(`${t(info.desc)} · ${t(info.note)}`);
        if (info.thresholds)
            this._thresholdRows(settings, t, row, key);
        return row;
    }

    // Arrastar pela alça e soltar sobre outra linha: o indicador assume a posição dela.
    _dragAndDrop(settings, row, handle, key, order) {
        const source = new Gtk.DragSource({actions: Gdk.DragAction.MOVE});
        source.connect('prepare', () => Gdk.ContentProvider.new_for_value(key));
        source.connect('drag-begin', (src, _drag) => {
            src.set_icon(new Gtk.WidgetPaintable({widget: row}), 0, 0);
        });
        handle.add_controller(source);

        const target = Gtk.DropTarget.new(GObject.TYPE_STRING, Gdk.DragAction.MOVE);
        target.connect('drop', (_target, dragged) => {
            if (dragged === key)
                return false;
            const next = order().filter(k => k !== dragged);
            next.splice(next.indexOf(key), 0, dragged);
            settings.set_strv('panel-order', next);
            return true;
        });
        row.add_controller(target);
    }

    // Limiares próprios (thresholds-override): ausente = usa os gerais.
    _thresholdRows(settings, t, row, key) {
        const read = () => settings.get_value('thresholds-override').deep_unpack();
        const own = read()[key];
        const useGeneral = new Adw.SwitchRow({title: t('Use general thresholds'), active: !own});
        const warn = spinRow(t('Yellow from (%)'), null, 1, 100, own ? own[0] : settings.get_int('warn-threshold'));
        const crit = spinRow(t('Red from (%)'), null, 1, 100, own ? own[1] : settings.get_int('crit-threshold'));

        const write = () => {
            const all = read();
            if (useGeneral.active)
                delete all[key];
            else
                all[key] = [warn.value, Math.max(warn.value, crit.value)];
            settings.set_value('thresholds-override', new GLib.Variant('a{s(ii)}', all));
        };
        const sync = () => {
            warn.sensitive = crit.sensitive = !useGeneral.active;
        };
        useGeneral.connect('notify::active', () => {
            sync();
            write();
        });
        warn.connect('notify::value', () => {
            if (crit.value < warn.value)
                crit.value = warn.value;
            if (!useGeneral.active)
                write();
        });
        crit.connect('notify::value', () => {
            if (warn.value > crit.value)
                warn.value = crit.value;
            if (!useGeneral.active)
                write();
        });
        sync();
        row.add_row(useGeneral);
        row.add_row(warn);
        row.add_row(crit);
    }

    // ------------------------------------------------------------------ About

    _aboutPage(window, t) {
        const page = new Adw.PreferencesPage({title: t('About'), icon_name: 'help-about-symbolic'});

        const header = new Adw.PreferencesGroup();
        const box = new Gtk.Box({orientation: Gtk.Orientation.VERTICAL, spacing: 8, margin_top: 12, margin_bottom: 12});
        box.append(new Gtk.Image({icon_name: 'claude-status-symbolic', pixel_size: 96, css_classes: ['dim-label']}));
        box.append(new Gtk.Label({label: this.metadata.name, css_classes: ['title-1']}));
        box.append(new Gtk.Label({
            label: t('Context and plan usage of your Claude Code sessions, right in the top panel.'),
            wrap: true,
            justify: Gtk.Justification.CENTER,
            css_classes: ['dim-label'],
        }));
        header.add(box);
        page.add(header);

        const details = new Adw.PreferencesGroup({
            description: t('No network access, no credentials: the data comes from the Claude Code statusline.'),
        });
        details.add(new Adw.ActionRow({title: t('Version'), subtitle: String(this.metadata.version)}));
        for (const [title, uri] of [[t('Source code'), REPO], [t('Report an issue'), `${REPO}/issues`]]) {
            const link = new Adw.ActionRow({title, subtitle: uri, activatable: true});
            link.add_suffix(new Gtk.Image({icon_name: 'adw-external-link-symbolic'}));
            link.connect('activated', () => openUri(window, uri));
            details.add(link);
        }
        page.add(details);
        return page;
    }
}
