// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Snap layouts: Win+Z shows layouts for the active window and snaps it into the area chosen with
// the mouse or the keyboard. It's a scene effect, so the picker has the keyboard and the mouse
// while it shows. Each screen draws a Picker; only the active window's screen shows the layouts.

import QtQuick
import org.kde.kwin
import org.kde.ki18n

SceneEffect {
    id: effect

    // KWin's own effects and scripts aren't in OrielOS's translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-snaplayouts"
    }

    // Each layout's areas, as fractions of the screen's usable area (without the taskbar).
    readonly property var layouts: [
        [
            { x: 0, y: 0, width: 1 / 2, height: 1, name: effect.l10n.i18nc("@action A snap area", "Left half") },
            { x: 1 / 2, y: 0, width: 1 / 2, height: 1, name: effect.l10n.i18nc("@action A snap area", "Right half") },
        ],
        [
            { x: 0, y: 0, width: 1 / 3, height: 1, name: effect.l10n.i18nc("@action A snap area", "Left third") },
            { x: 1 / 3, y: 0, width: 1 / 3, height: 1, name: effect.l10n.i18nc("@action A snap area", "Middle third") },
            { x: 2 / 3, y: 0, width: 1 / 3, height: 1, name: effect.l10n.i18nc("@action A snap area", "Right third") },
        ],
        [
            { x: 0, y: 0, width: 2 / 3, height: 1, name: effect.l10n.i18nc("@action A snap area", "Left two thirds") },
            { x: 2 / 3, y: 0, width: 1 / 3, height: 1, name: effect.l10n.i18nc("@action A snap area", "Right third, beside two thirds") },
        ],
        [
            { x: 0, y: 0, width: 1 / 2, height: 1 / 2, name: effect.l10n.i18nc("@action A snap area", "Top left quarter") },
            { x: 1 / 2, y: 0, width: 1 / 2, height: 1 / 2, name: effect.l10n.i18nc("@action A snap area", "Top right quarter") },
            { x: 0, y: 1 / 2, width: 1 / 2, height: 1 / 2, name: effect.l10n.i18nc("@action A snap area", "Bottom left quarter") },
            { x: 1 / 2, y: 1 / 2, width: 1 / 2, height: 1 / 2, name: effect.l10n.i18nc("@action A snap area", "Bottom right quarter") },
        ],
    ]

    // The window the picker was opened for. It's a KWin Window, which QML can't name as a type,
    // and it becomes null if the window closes meanwhile.
    property var target: null

    // Show the layouts for the active window, if it's one that can be moved and resized.
    function open() {
        const window = Workspace.activeWindow;
        if (!window || !window.normalWindow || !window.moveable || !window.resizeable || window.fullScreen) {
            return;
        }
        effect.target = window;
        effect.visible = true;
    }

    function close() {
        effect.visible = false;
        effect.target = null;
    }

    // Snap the window into one area of a layout.
    function snap(area) {
        const window = effect.target;
        effect.close();
        if (!window) {
            return;
        }
        const usable = Workspace.clientArea(Workspace.MaximizeArea, window);
        window.setMaximize(false, false);
        window.tile = null;
        const left = Math.round(usable.x + usable.width * area.x);
        const top = Math.round(usable.y + usable.height * area.y);
        window.frameGeometry = Qt.rect(left, top, Math.round(usable.x + usable.width * (area.x + area.width)) - left,
            Math.round(usable.y + usable.height * (area.y + area.height)) - top);
        Workspace.activeWindow = window;
    }

    delegate: Picker {}

    ShortcutHandler {
        name: "Snap Layouts"
        text: effect.l10n.i18nc("@action Global shortcut", "Show snap layouts")
        sequence: "Meta+Z"
        onActivated: effect.visible ? effect.close() : effect.open()
    }
}
