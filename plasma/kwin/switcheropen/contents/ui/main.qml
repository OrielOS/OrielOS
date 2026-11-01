// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Ctrl+Alt+Tab as Windows has it: the window switcher, which stays open after the keys are let go.
// It looks like OrielOS's Alt+Tab (plasma/kwin/switcher; keep the two in step): the screen dims and
// a pane holds this desktop's windows, the one in use first. The arrow keys, Tab and Shift+Tab or
// Ctrl+Alt+Tab again move; Enter, Space or a click switches; Delete closes the selected window;
// Escape or a click beside the pane closes the switcher.

import QtQuick
import org.kde.kwin
import org.kde.ki18n

SceneEffect {
    id: effect

    // KWin's own effects and scripts aren't in OrielOS's translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-switcheropen"
    }

    // The windows to switch between, the one on top first. KWin Windows, which QML can't name.
    property var windows: []
    property int current: 0

    // This desktop's windows that Alt+Tab would list, from the top of the stack down, so the
    // window in use comes first and the one used before it second.
    function switchable(): var {
        return Workspace.stackingOrder.slice().reverse().filter(window => window.normalWindow && !window.skipSwitcher && !window.deleted
            && (window.onAllDesktops || window.desktops.includes(Workspace.currentDesktop)));
    }

    function open() {
        effect.windows = effect.switchable();
        // As in Windows, the window used before this one is chosen to begin with.
        effect.current = effect.windows.length > 1 ? 1 : 0;
        effect.visible = true;
    }

    function close() {
        effect.visible = false;
        effect.windows = [];
    }

    function move(step: int) {
        const count = effect.windows.length;
        if (count > 0) {
            effect.current = (effect.current + step + count) % count;
        }
    }

    function activate(index: int) {
        const window = effect.windows[index];
        effect.close();
        if (window) {
            Workspace.activeWindow = window;
        }
    }

    // Closes a window and keeps the switcher open on the rest.
    function closeWindow(index: int) {
        const window = effect.windows[index];
        if (!window || !window.closeable) {
            return;
        }
        window.closeWindow();
        const rest = effect.windows.filter(other => other !== window);
        effect.windows = rest;
        effect.current = Math.min(effect.current, Math.max(0, rest.length - 1));
    }

    delegate: Switcher {}

    ShortcutHandler {
        name: "OrielOS Window Switcher Stays Open"
        text: effect.l10n.i18nc("@action Global shortcut", "Show the window switcher until a window is chosen")
        sequence: "Ctrl+Alt+Tab"
        onActivated: effect.visible ? effect.move(1) : effect.open()
    }
}
