// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The snap bar, as Windows drops it down: while a window is dragged near the top of the screen,
// the layouts show in a row at the top centre, and letting go over one of their areas snaps the
// window there. KWin holds the pointer during the drag, so the bar takes no input of its own: the
// area under the pointer is worked out from the pointer's position. Letting go at the very top
// edge, above the bar, still maximises the window, as KWin does.

import QtQuick
// Named: since KWin 6.8, org.kde.kwin has a Window type of its own (KWin's windows, which QML
// can't create), which would hide Qt's.
import QtQuick.Window as QtWindow
import org.kde.kirigami as Kirigami
import org.kde.kwin

QtWindow.Window {
    id: bar

    // The scene effect in main.qml, for the layouts and snapping.
    required property var effect

    // The window being dragged.
    property QtObject window: null
    // The area under the pointer, an index into all the layouts' areas, or -1.
    property int current: -1
    // Every area of every layout, in order.
    readonly property var areas: bar.effect.layouts.reduce((all, layout) => all.concat(layout), [])
    // Each layout's drawing and the space between them, in pixels; smaller than the picker's.
    readonly property real tileWidth: Kirigami.Units.gridUnit * 4.5
    readonly property real tileHeight: Kirigami.Units.gridUnit * 2.5
    readonly property real tileSpacing: Kirigami.Units.gridUnit * 0.6
    readonly property real padding: Kirigami.Units.largeSpacing
    // The gap above the bar, where letting go maximises instead.
    readonly property real topGap: Kirigami.Units.gridUnit
    // How near the top the pointer brings the bar down.
    readonly property real reach: Kirigami.Units.gridUnit * 6

    flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput
    color: "transparent"
    width: Math.ceil(bar.effect.layouts.length * (bar.tileWidth + bar.tileSpacing) - bar.tileSpacing + bar.padding * 2)
    height: Math.ceil(bar.tileHeight + bar.padding * 2)
    visible: false

    // The index of a layout's first area among all of them.
    function firstArea(layoutIndex: int): int {
        let first = 0;
        for (let i = 0; i < layoutIndex; ++i) {
            first += bar.effect.layouts[i].length;
        }
        return first;
    }

    // A drag began: follow it if it moves a window that can be snapped.
    function start(window: QtObject) {
        if (!window || !window.normalWindow || !window.resizeable || window.fullScreen) {
            return;
        }
        bar.window = window;
        bar.current = -1;
    }

    // The pointer moved during the drag.
    function follow() {
        if (!bar.window) {
            return;
        }
        const pointer = Workspace.cursorPos;
        const output = Workspace.screenAt(pointer);
        if (!output) {
            return;
        }
        const screen = output.geometry;
        bar.x = Math.round(screen.x + (screen.width - bar.width) / 2);
        bar.y = Math.round(screen.y + bar.topGap);
        const near = pointer.y - screen.y < bar.reach && Math.abs(pointer.x - (screen.x + screen.width / 2)) < bar.width / 2 + bar.reach;
        bar.visible = near;
        bar.current = near ? bar.areaAt(pointer.x - bar.x - bar.padding, pointer.y - bar.y - bar.padding) : -1;
    }

    // The area at a point, in pixels from the top left of the first layout, or -1.
    function areaAt(px: real, py: real): int {
        const layout = Math.floor(px / (bar.tileWidth + bar.tileSpacing));
        if (layout < 0 || layout >= bar.effect.layouts.length || py < 0 || py >= bar.tileHeight) {
            return -1;
        }
        const lx = (px - layout * (bar.tileWidth + bar.tileSpacing)) / bar.tileWidth;
        const ly = py / bar.tileHeight;
        const areas = bar.effect.layouts[layout];
        for (let i = 0; i < areas.length; ++i) {
            const area = areas[i];
            if (lx >= area.x && lx < area.x + area.width && ly >= area.y && ly < area.y + area.height) {
                return bar.firstArea(layout) + i;
            }
        }
        return -1;
    }

    // The drag ended: snap into the area under the pointer, if there is one.
    function drop() {
        const window = bar.window;
        const area = bar.visible && bar.current >= 0 ? bar.areas[bar.current] : null;
        bar.window = null;
        bar.visible = false;
        bar.current = -1;
        if (window && area) {
            // KWin settles the dragged window's place after telling scripts the drag ended, so the
            // snap waits until it has.
            Qt.callLater(bar.effect.snapWindow, window, area);
        }
    }

    // Sill's pane, as the picker's card.
    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.cornerRadius * 2
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)

        Row {
            x: bar.padding
            y: bar.padding
            spacing: bar.tileSpacing

            Repeater {
                model: bar.effect.layouts

                delegate: LayoutTile {
                    required property var modelData
                    required property int index

                    width: bar.tileWidth
                    height: bar.tileHeight
                    areas: modelData
                    firstIndex: bar.firstArea(index)
                    current: bar.current
                }
            }
        }
    }
}
