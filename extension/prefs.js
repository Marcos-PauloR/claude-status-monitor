// Claude Status Monitor — preferências (Adw): limiares de cor, inatividade, campos e posição no painel.

import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

// [chave, rótulo, descrição]
const FIELDS = [
    ['model', 'model', 'Model of the most recent window'],
    ['ctx', 'ctx', 'Context used by the most recent window'],
    ['session', 'session', 'Account usage in the current 5-hour session'],
    ['resets', 'resets', 'Time until the session usage resets'],
    ['compacts', 'compacts', 'Compacts in the most recent window'],
    ['weekly', 'weekly', 'Account usage in the current week'],
];
const BOXES = [['left', 'Left'], ['center', 'Center'], ['right', 'Right']];

function spinRow(settings, key, title, subtitle, lower, upper) {
    const row = new Adw.SpinRow({
        title,
        subtitle,
        adjustment: new Gtk.Adjustment({lower, upper, step_increment: 1, page_increment: 10}),
    });
    settings.bind(key, row, 'value', Gio.SettingsBindFlags.DEFAULT);
    return row;
}

export default class ClaudeStatusPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        const ids = [];
        const watch = (key, fn) => ids.push(settings.connect(`changed::${key}`, fn));
        window.connect('close-request', () => ids.forEach(id => settings.disconnect(id)));

        // Crítico nunca fica abaixo do aviso.
        watch('warn-threshold', () => {
            if (settings.get_int('crit-threshold') < settings.get_int('warn-threshold'))
                settings.set_int('crit-threshold', settings.get_int('warn-threshold'));
        });
        watch('crit-threshold', () => {
            if (settings.get_int('warn-threshold') > settings.get_int('crit-threshold'))
                settings.set_int('warn-threshold', settings.get_int('crit-threshold'));
        });

        const page = new Adw.PreferencesPage();
        window.add(page);

        const colors = new Adw.PreferencesGroup({
            title: 'Colors',
            description: 'The panel follows the worst of ctx, session and weekly.',
        });
        colors.add(spinRow(settings, 'warn-threshold', 'Warning (%)', 'Yellow from this value on', 1, 100));
        colors.add(spinRow(settings, 'crit-threshold', 'Critical (%)', 'Red from this value on', 1, 100));
        page.add(colors);

        const windows = new Adw.PreferencesGroup({title: 'Windows'});
        windows.add(spinRow(settings, 'inactive-minutes', 'Inactive after (minutes)',
            'Windows without updates for this long are hidden', 1, 1440));
        page.add(windows);

        const fields = new Adw.PreferencesGroup({title: 'Panel fields'});
        for (const [key, title, subtitle] of FIELDS) {
            const row = new Adw.SwitchRow({title, subtitle});
            const sync = () => (row.active = settings.get_strv('panel-fields').includes(key));
            sync();
            row.connect('notify::active', () => {
                const current = settings.get_strv('panel-fields');
                if (row.active === current.includes(key))
                    return;
                // Mantém a ordem original dos campos.
                const next = FIELDS.map(([k]) => k).filter(k => (k === key ? row.active : current.includes(k)));
                settings.set_strv('panel-fields', next);
            });
            watch('panel-fields', sync);
            fields.add(row);
        }
        page.add(fields);

        const position = new Adw.PreferencesGroup({title: 'Panel position'});
        const box = new Adw.ComboRow({
            title: 'Area',
            model: Gtk.StringList.new(BOXES.map(([, label]) => label)),
        });
        const syncBox = () => (box.selected = Math.max(0, BOXES.findIndex(([nick]) => nick === settings.get_string('panel-box'))));
        syncBox();
        box.connect('notify::selected', () => {
            const nick = BOXES[box.selected]?.[0];
            if (nick && nick !== settings.get_string('panel-box'))
                settings.set_string('panel-box', nick);
        });
        watch('panel-box', syncBox);
        position.add(box);
        position.add(spinRow(settings, 'panel-index', 'Order', 'Position inside the area (0 = first)', 0, 20));
        page.add(position);
    }
}
