// Hacker Tools: a live system readout in the top bar and an F12 drop-down terminal.
// Each feature is set up inside its own try/catch so one failing never takes down the other.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const STATS_INTERVAL_S = 3;
const TAILSCALE_INTERVAL_S = 60;
const SLIDE_MS = 180;
const SKIP_IFACES = /^(lo|tailscale|veth|docker|br-|virbr)/;

const decoder = new TextDecoder();

function readFile(path) {
    const [ok, bytes] = GLib.file_get_contents(path);
    return ok ? decoder.decode(bytes) : '';
}

function humanRate(bytesPerSec) {
    if (bytesPerSec >= 1048576)
        return `${(bytesPerSec / 1048576).toFixed(1)}M`;
    if (bytesPerSec >= 1024)
        return `${Math.round(bytesPerSec / 1024)}K`;
    return `${Math.round(bytesPerSec)}B`;
}

class SystemStats {
    constructor(uuid) {
        this._prevCpu = null;
        this._prevNet = null;
        this._tailscaleIp = '';

        this.button = new PanelMenu.Button(0.0, 'Hacker Stats', false);
        this._label = new St.Label({
            text: 'CPU --% │ RAM --',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'hacker-stats-label',
        });
        this.button.add_child(this._label);

        const btop = new PopupMenu.PopupMenuItem('Open system monitor (btop)');
        btop.connect('activate', () => this._spawn(['ptyxis', '--new-window', '-x', 'btop']));
        this.button.menu.addMenuItem(btop);

        Main.panel.addToStatusArea(uuid, this.button, 0, 'right');

        this._update();
        this._updateTailscale();
        this._statsTimer = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, STATS_INTERVAL_S, () => {
            this._update();
            return GLib.SOURCE_CONTINUE;
        });
        this._tsTimer = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, TAILSCALE_INTERVAL_S, () => {
            this._updateTailscale();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _spawn(argv) {
        try {
            Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE);
        } catch (e) {
            logError(e, 'hacker-tools: spawn failed');
        }
    }

    _cpuPercent() {
        const f = readFile('/proc/stat').split('\n')[0].trim().split(/\s+/).slice(1, 9).map(Number);
        const idle = f[3] + f[4];
        const total = f.reduce((a, b) => a + b, 0);
        let pct = 0;
        if (this._prevCpu) {
            const dt = total - this._prevCpu.total;
            pct = dt > 0 ? Math.round(100 * (1 - (idle - this._prevCpu.idle) / dt)) : 0;
        }
        this._prevCpu = {idle, total};
        return pct;
    }

    _ramUsed() {
        const info = {};
        for (const line of readFile('/proc/meminfo').split('\n')) {
            const m = line.match(/^(\w+):\s+(\d+)/);
            if (m)
                info[m[1]] = Number(m[2]);
        }
        return ((info.MemTotal - info.MemAvailable) / 1048576).toFixed(1);
    }

    _netRates() {
        let rx = 0, tx = 0;
        for (const line of readFile('/proc/net/dev').split('\n').slice(2)) {
            const [name, rest] = line.split(':');
            if (!rest || SKIP_IFACES.test(name.trim()))
                continue;
            const f = rest.trim().split(/\s+/).map(Number);
            rx += f[0];
            tx += f[8];
        }
        const now = GLib.get_monotonic_time() / 1e6;
        let down = 0, up = 0;
        if (this._prevNet) {
            const dt = now - this._prevNet.time;
            down = Math.max(0, (rx - this._prevNet.rx) / dt);
            up = Math.max(0, (tx - this._prevNet.tx) / dt);
        }
        this._prevNet = {rx, tx, time: now};
        return [down, up];
    }

    _update() {
        try {
            const cpu = String(this._cpuPercent()).padStart(2, ' ');
            const [down, up] = this._netRates();
            let text = `CPU ${cpu}% │ RAM ${this._ramUsed()}G │ ↓${humanRate(down)} ↑${humanRate(up)}`;
            if (this._tailscaleIp)
                text += ` │ TS ${this._tailscaleIp}`;
            this._label.text = text;
        } catch (e) {
            logError(e, 'hacker-tools: stats update failed');
        }
    }

    _updateTailscale() {
        try {
            const proc = Gio.Subprocess.new(['tailscale', 'ip', '-4'],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
            proc.communicate_utf8_async(null, null, (p, res) => {
                try {
                    const [, out] = p.communicate_utf8_finish(res);
                    this._tailscaleIp = p.get_successful() ? out.trim().split('\n')[0] : '';
                } catch {
                    this._tailscaleIp = '';
                }
            });
        } catch {
            this._tailscaleIp = '';
        }
    }

    destroy() {
        if (this._statsTimer)
            GLib.source_remove(this._statsTimer);
        if (this._tsTimer)
            GLib.source_remove(this._tsTimer);
        this._statsTimer = this._tsTimer = 0;
        this.button.destroy();
    }
}

class DropdownTerminal {
    constructor(settings) {
        this._settings = settings;
        this._window = null;
        this._waitId = 0;
        this._waitTimeout = 0;

        Main.wm.addKeybinding('dropdown-terminal', settings, Meta.KeyBindingFlags.NONE,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW, () => this.toggle());
    }

    toggle() {
        if (!this._window) {
            this._launch();
            return;
        }
        const win = this._window;
        if (win.has_focus() && !win.minimized)
            this._slideUp(win);
        else
            this._show(win);
    }

    _launch() {
        if (this._waitId)
            return;
        // Ptyxis is single-instance, so catch the next Ptyxis window that appears and adopt it.
        this._waitId = global.display.connect('window-created', (display, win) => {
            if (!/ptyxis/i.test(win.get_wm_class() ?? ''))
                return;
            this._stopWaiting();
            this._adopt(win);
        });
        this._waitTimeout = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, () => {
            this._waitTimeout = 0;
            this._stopWaiting();
            return GLib.SOURCE_REMOVE;
        });
        try {
            Gio.Subprocess.new(['ptyxis', '--new-window'], Gio.SubprocessFlags.NONE);
        } catch (e) {
            this._stopWaiting();
            logError(e, 'hacker-tools: could not start ptyxis');
        }
    }

    _stopWaiting() {
        if (this._waitId)
            global.display.disconnect(this._waitId);
        if (this._waitTimeout)
            GLib.source_remove(this._waitTimeout);
        this._waitId = this._waitTimeout = 0;
    }

    _adopt(win) {
        this._window = win;
        this._unmanagedId = win.connect('unmanaged', () => {
            this._window = null;
        });
        const actor = win.get_compositor_private();
        const firstFrameId = actor.connect('first-frame', () => {
            actor.disconnect(firstFrameId);
            this._show(win);
        });
    }

    _place(win) {
        if (win.is_maximized())
            win.unmaximize();
        const area = Main.layoutManager.getWorkAreaForMonitor(Main.layoutManager.primaryIndex);
        const height = Math.round(area.height * this._settings.get_double('dropdown-height'));
        win.move_resize_frame(false, area.x, area.y, area.width, height);
        if (!win.is_above())
            win.make_above();
        if (!win.is_on_all_workspaces())
            win.stick();
    }

    _show(win) {
        if (win.minimized)
            win.unminimize();
        this._place(win);
        win.activate(global.get_current_time());
        const actor = win.get_compositor_private();
        if (!actor)
            return;
        actor.remove_all_transitions();
        actor.translation_y = -actor.height;
        actor.ease({
            translation_y: 0,
            duration: SLIDE_MS,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        });
    }

    _slideUp(win) {
        const actor = win.get_compositor_private();
        if (!actor) {
            win.minimize();
            return;
        }
        actor.remove_all_transitions();
        actor.ease({
            translation_y: -actor.height,
            duration: SLIDE_MS,
            mode: Clutter.AnimationMode.EASE_IN_QUAD,
            onStopped: () => {
                win.minimize();
                actor.translation_y = 0;
            },
        });
    }

    destroy() {
        Main.wm.removeKeybinding('dropdown-terminal');
        this._stopWaiting();
        if (this._window && this._unmanagedId)
            this._window.disconnect(this._unmanagedId);
        this._window = null;
    }
}

export default class HackerToolsExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        try {
            this._stats = new SystemStats(this.uuid);
        } catch (e) {
            logError(e, 'hacker-tools: stats failed to start');
        }
        try {
            this._dropdown = new DropdownTerminal(this._settings);
        } catch (e) {
            logError(e, 'hacker-tools: drop-down terminal failed to start');
        }
    }

    disable() {
        this._stats?.destroy();
        this._dropdown?.destroy();
        this._stats = this._dropdown = this._settings = null;
    }
}
