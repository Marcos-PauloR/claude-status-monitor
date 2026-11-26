// Leitura do config único (~/.config/claude-status/config). A extensão usa só os apelidos de
// conta (account.<id>=nome); limiares, idioma e tema do GNOME ficam no GSettings.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

export const safeId = s => String(s).replace(/[^A-Za-z0-9_-]/g, '_');

export function configFile() {
    return GLib.build_filenamev([GLib.get_user_config_dir(), 'claude-status', 'config']);
}

export function parseConfig(text) {
    const labels = {};
    for (const line of text.split('\n')) {
        const i = line.indexOf('=');
        if (i < 0)
            continue;
        const key = line.slice(0, i).trim(), value = line.slice(i + 1).trim();
        if (key.startsWith('account.') && value) {
            const id = safeId(key.slice('account.'.length));
            if (id)
                labels[id] = value;
        }
    }
    return {labels};
}

export function readConfig(path = configFile()) {
    try {
        const [, bytes] = Gio.File.new_for_path(path).load_contents(null);
        return parseConfig(new TextDecoder().decode(bytes));
    } catch {
        return {labels: {}};
    }
}
