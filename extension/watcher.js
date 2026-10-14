// Acompanha o diretório de snapshots com Gio.FileMonitor e mantém um cache em memória.
// Cada evento relê no máximo um arquivo. Um timer de 30 s re-renderiza (expira janelas
// inativas) e recria o diretório/monitor se o cache tiver sido apagado.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import {isSnapshotName, readSnapshot} from './store.js';

const TICK_SECONDS = 30;
const DEBOUNCE_MS = 150;

export class SnapshotWatcher {
    /**
     * @param {string} path diretório de sessões
     * @param {(snapshots: Iterable<object>) => void} onChange
     */
    constructor(path, onChange) {
        this._dir = Gio.File.new_for_path(path);
        this._onChange = onChange;
        this._cache = new Map();
        this._monitor = null;
        this._monitorId = 0;
        this._debounceId = 0;
        this._tickId = 0;
    }

    start() {
        this._watch();
        this._tickId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, TICK_SECONDS, () => {
            if (!this._dir.query_exists(null))
                this._watch();
            else
                this._emit();
            return GLib.SOURCE_CONTINUE;
        });
        this._emit();
    }

    stop() {
        if (this._tickId)
            GLib.source_remove(this._tickId);
        if (this._debounceId)
            GLib.source_remove(this._debounceId);
        this._tickId = this._debounceId = 0;
        this._unwatch();
        this._cache.clear();
        this._onChange = null;
    }

    get snapshots() {
        return this._cache.values();
    }

    _watch() {
        this._unwatch();
        this._cache.clear();
        try {
            this._dir.make_directory_with_parents(null);
        } catch (e) {
            if (!e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.EXISTS))
                console.warn(`claude-status: não foi possível criar ${this._dir.get_path()}: ${e.message}`);
        }
        try {
            this._monitor = this._dir.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
            this._monitorId = this._monitor.connect('changed', this._onEvent.bind(this));
            this._scan();
        } catch (e) {
            console.warn(`claude-status: não foi possível monitorar ${this._dir.get_path()}: ${e.message}`);
        }
        this._emit();
    }

    _unwatch() {
        if (this._monitor) {
            this._monitor.disconnect(this._monitorId);
            this._monitor.cancel();
        }
        this._monitor = null;
        this._monitorId = 0;
    }

    _scan() {
        const iter = this._dir.enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
        let info;
        while ((info = iter.next_file(null)) !== null) {
            if (isSnapshotName(info.get_name()))
                this._load(this._dir.get_child(info.get_name()));
        }
        iter.close(null);
    }

    _load(file) {
        const snapshot = readSnapshot(file);
        if (snapshot)
            this._cache.set(file.get_basename(), snapshot);
        else
            this._cache.delete(file.get_basename());
    }

    _onEvent(_monitor, file, otherFile, event) {
        const E = Gio.FileMonitorEvent;
        if (file.equal(this._dir)) {
            if (event === E.DELETED || event === E.MOVED_OUT)
                this._watch();
            return;
        }
        switch (event) {
        case E.CHANGES_DONE_HINT:
        case E.MOVED_IN:
            if (isSnapshotName(file.get_basename()))
                this._load(file);
            break;
        case E.RENAMED: // escrita atômica da ponte: .tmp -> <id>.json
            this._cache.delete(file.get_basename());
            if (isSnapshotName(otherFile.get_basename()))
                this._load(otherFile);
            break;
        case E.DELETED:
        case E.MOVED_OUT:
            this._cache.delete(file.get_basename());
            break;
        default:
            return;
        }
        this._schedule();
    }

    _schedule() {
        if (this._debounceId)
            return;
        this._debounceId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, DEBOUNCE_MS, () => {
            this._debounceId = 0;
            this._emit();
            return GLib.SOURCE_REMOVE;
        });
    }

    _emit() {
        this._onChange?.(this._cache.values());
    }
}
