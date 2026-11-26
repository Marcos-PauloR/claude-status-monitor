// Temas de cores (docs/superpowers/specs/2026-11-26-contas-fixar-temas-design.md §2.4).
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

export const DEFAULT_THEME = Object.freeze({
    id: 'default', name: 'Default', normal: '', warn: '#f6d32d', crit: '#ff7b63', label: '', bar: '#78aeed', accent: '',
});
const COLOR_KEYS = ['normal', 'warn', 'crit', 'label', 'bar', 'accent'];

// Cada aviso sai uma vez só: o tema é relido a cada atualização do painel.
const warned = new Set();
function warnOnce(msg) {
    if (!warned.has(msg)) {
        warned.add(msg);
        console.warn(msg);
    }
}

export const isColor = s => /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(s);

export function themeDirs() {
    return [
        GLib.build_filenamev([GLib.get_user_config_dir(), 'claude-status', 'themes']),
        GLib.build_filenamev([GLib.get_user_data_dir(), 'claude-status', 'themes']),
    ];
}

export function parseTheme(id, text) {
    const theme = {...DEFAULT_THEME, id, name: id === 'default' ? DEFAULT_THEME.name : id};
    const errors = [];
    for (const line of text.split('\n')) {
        const i = line.indexOf('=');
        if (i < 0)
            continue;
        const key = line.slice(0, i).trim(), value = line.slice(i + 1).trim();
        if (key === 'name' && value)
            theme.name = value;
        else if (COLOR_KEYS.includes(key) && value) {
            if (isColor(value))
                theme[key] = value;
            else
                errors.push(`cor inválida em ${key} (${value})`);
        }
    }
    return {theme, errors};
}

function readText(path) {
    try {
        const [, bytes] = Gio.File.new_for_path(path).load_contents(null);
        return new TextDecoder().decode(bytes);
    } catch {
        return null;
    }
}

export function loadTheme(id, dirs = themeDirs()) {
    if (!/^[A-Za-z0-9_-]+$/.test(id ?? ''))
        id = 'default';
    for (const dir of dirs) {
        const text = readText(GLib.build_filenamev([dir, `${id}.theme`]));
        if (text === null)
            continue;
        const {theme, errors} = parseTheme(id, text);
        errors.forEach(e => warnOnce(`claude-status: tema ${id}: ${e}`));
        return theme;
    }
    if (id !== 'default')
        warnOnce(`claude-status: tema não encontrado: ${id} (usando default)`);
    return {...DEFAULT_THEME};
}

export function listThemes(dirs = themeDirs()) {
    const found = new Map();
    for (const dir of dirs) {
        let en;
        try {
            en = Gio.File.new_for_path(dir).enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
        } catch {
            continue;
        }
        for (let info; (info = en.next_file(null));) {
            const m = info.get_name().match(/^([A-Za-z0-9_-]+)\.theme$/);
            if (m && !found.has(m[1]))
                found.set(m[1], loadTheme(m[1], [dir]).name);
        }
    }
    if (!found.has('default'))
        found.set('default', DEFAULT_THEME.name);
    return [...found].map(([id, name]) => ({id, name}))
        .sort((a, b) => (a.id === 'default' ? -1 : b.id === 'default' ? 1 : a.id.localeCompare(b.id)));
}
