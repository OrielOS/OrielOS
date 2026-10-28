// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Snap layouts: Win+Z shows layouts for the active window and snaps it into the area chosen with
// the mouse or the keyboard. It's a scene effect, so the picker has the keyboard and the mouse
// while it shows. Each screen draws a Picker; only the active window's screen shows the layouts.
// Hovering over a window's maximise button opens the same layouts as a small menu under the button
// (OrielOS's window frames invoke the "Snap Layouts Menu" action), without dimming the screen.

import QtQuick
import org.kde.kwin
import org.kde.ki18n

SceneEffect {
    id: effect

    // KWin's own effects and scripts aren't in OrielOS's translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-snaplayouts"
    }

    // Each layout's areas, as fractions of the screen's usable area (without the taskbar), in Sill's
    // order: two rows of three in the menu.
    readonly property var layouts: [
        [
            { x: 0, y: 0, width: 1 / 2, height: 1, name: effect.l10n.i18nc("@action A snap area", "Left half") },
            { x: 1 / 2, y: 0, width: 1 / 2, height: 1, name: effect.l10n.i18nc("@action A snap area", "Right half") },
        ],
        [
            { x: 0, y: 0, width: 2 / 3, height: 1, name: effect.l10n.i18nc("@action A snap area", "Left two thirds") },
            { x: 2 / 3, y: 0, width: 1 / 3, height: 1, name: effect.l10n.i18nc("@action A snap area", "Right third, beside two thirds") },
        ],
        [
            { x: 0, y: 0, width: 1 / 3, height: 1, name: effect.l10n.i18nc("@action A snap area", "Left third") },
            { x: 1 / 3, y: 0, width: 1 / 3, height: 1, name: effect.l10n.i18nc("@action A snap area", "Middle third") },
            { x: 2 / 3, y: 0, width: 1 / 3, height: 1, name: effect.l10n.i18nc("@action A snap area", "Right third") },
        ],
        [
            { x: 0, y: 0, width: 1 / 2, height: 1, name: effect.l10n.i18nc("@action A snap area", "Left half, beside two quarters") },
            { x: 1 / 2, y: 0, width: 1 / 2, height: 1 / 2, name: effect.l10n.i18nc("@action A snap area", "Top right quarter") },
            { x: 1 / 2, y: 1 / 2, width: 1 / 2, height: 1 / 2, name: effect.l10n.i18nc("@action A snap area", "Bottom right quarter") },
        ],
        [
            { x: 0, y: 0, width: 1 / 2, height: 1 / 2, name: effect.l10n.i18nc("@action A snap area", "Top left quarter") },
            { x: 1 / 2, y: 0, width: 1 / 2, height: 1 / 2, name: effect.l10n.i18nc("@action A snap area", "Top right quarter") },
            { x: 0, y: 1 / 2, width: 1 / 2, height: 1 / 2, name: effect.l10n.i18nc("@action A snap area", "Bottom left quarter") },
            { x: 1 / 2, y: 1 / 2, width: 1 / 2, height: 1 / 2, name: effect.l10n.i18nc("@action A snap area", "Bottom right quarter") },
        ],
        [
            { x: 0, y: 0, width: 1 / 4, height: 1, name: effect.l10n.i18nc("@action A snap area", "Left quarter") },
            { x: 1 / 4, y: 0, width: 1 / 2, height: 1, name: effect.l10n.i18nc("@action A snap area", "Middle half") },
            { x: 3 / 4, y: 0, width: 1 / 4, height: 1, name: effect.l10n.i18nc("@action A snap area", "Right quarter") },
        ],
    ]

    // The window the picker was opened for. It's a KWin Window, which QML can't name as a type; as a
    // QtObject property it becomes null when the window object goes.
    property QtObject target: null
    // The highlighted area, an index into all the layouts' areas. It's the effect's, not each
    // screen's, so whichever screen KWin sends the keys to moves the highlight that shows.
    property int current: 0
    // Whether the layouts show as the maximise button's menu rather than over the dimmed screen.
    property bool menu: false

    // If the window closes while the layouts show, there's nothing left to snap. KWin keeps a closed
    // window's object for its closing animation, so its closed signal comes first.
    onTargetChanged: {
        if (effect.visible && !effect.target) {
            effect.close();
        }
    }

    Connections {
        target: effect.target
        ignoreUnknownSignals: true

        function onClosed() {
            effect.close();
        }
    }

    // Show the layouts for the active window, if it's one that can be moved and resized.
    function open() {
        const window = Workspace.activeWindow;
        if (!window || !window.normalWindow || !window.moveable || !window.resizeable || window.fullScreen) {
            return;
        }
        effect.target = window;
        effect.current = 0;
        effect.menu = false;
        effect.visible = true;
    }

    // Show the layouts as the menu of the maximise button of the active window.
    function openMenu() {
        effect.open();
        effect.menu = effect.visible;
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

    // No key of its own: OrielOS's window frames invoke it when the pointer rests on maximise.
    ShortcutHandler {
        name: "Snap Layouts Menu"
        text: effect.l10n.i18nc("@action Global shortcut", "Show snap layouts under the maximise button")
        onActivated: {
            if (!effect.visible) {
                effect.openMenu();
            }
        }
    }
}
