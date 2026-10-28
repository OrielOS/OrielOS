// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// One screen while the picker shows: its windows, dimmed, and on the active window's screen the
// layouts. An arrow key moves to the nearest area that way, Tab and Shift+Tab step through the
// areas in order, Enter or Space snaps, Escape or a click elsewhere closes. As the maximise
// button's menu, the screen isn't dimmed, the layouts sit in two rows of three under the button,
// and they close once the pointer leaves them and the button.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kwin

FocusScope {
    id: picker

    // The scene effect in main.qml, and the screen this copy is on.
    readonly property var effect: SceneView.effect
    readonly property var screen: SceneView.screen
    readonly property bool showsLayouts: picker.effect.target !== null && picker.effect.target.output === picker.screen
    // Every area of every layout, in order, so the keyboard can step through them.
    readonly property var areas: picker.effect.layouts.reduce((all, layout) => all.concat(layout), [])
    // Each layout's drawing, in grid units, and the space between two of them.
    readonly property real tileWidth: 8
    readonly property real tileHeight: 4.5
    readonly property real tileSpacing: 1
    // Layouts in a row: all of them over the dimmed screen, three in the menu.
    readonly property int columns: picker.effect.menu ? 3 : picker.effect.layouts.length
    // The maximise button of the window, in this screen's coordinates: OrielOS's frames put it
    // second from the right, 46 by 40 pixels.
    readonly property rect maximiseButton: picker.effect.target
        ? Qt.rect(picker.effect.target.x + picker.effect.target.width - 92 - picker.screen.geometry.x, picker.effect.target.y - picker.screen.geometry.y, 46, 40)
        : Qt.rect(0, 0, 0, 0)

    // The index in areas of each layout's first area.
    function firstArea(layoutIndex: int): int {
        let first = 0;
        for (let i = 0; i < layoutIndex; ++i) {
            first += picker.effect.layouts[i].length;
        }
        return first;
    }

    // The layout an area belongs to.
    function layoutOf(areaIndex: int): int {
        let layout = 0;
        while (layout + 1 < picker.effect.layouts.length && picker.firstArea(layout + 1) <= areaIndex) {
            ++layout;
        }
        return layout;
    }

    // An area as drawn, in grid units from the top left of the row of layouts.
    function drawnArea(areaIndex: int): rect {
        const area = picker.areas[areaIndex];
        const layout = picker.layoutOf(areaIndex);
        const column = layout % picker.columns;
        const row = Math.floor(layout / picker.columns);
        return Qt.rect(column * (picker.tileWidth + picker.tileSpacing) + area.x * picker.tileWidth,
            row * (picker.tileHeight + picker.tileSpacing) + area.y * picker.tileHeight, area.width * picker.tileWidth, area.height * picker.tileHeight);
    }

    // The menu closes a moment after the pointer leaves both it and the maximise button.
    function pointerAt(x: real, y: real) {
        if (!picker.effect.menu || !picker.showsLayouts) {
            return;
        }
        const inside = (rect, px, py) => px >= rect.x && px < rect.x + rect.width && py >= rect.y && py < rect.y + rect.height;
        const onCard = inside(Qt.rect(card.x, card.y, card.width, card.height), x, y);
        if (onCard || inside(picker.maximiseButton, x, y)) {
            leaveTimer.stop();
        } else if (!leaveTimer.running) {
            leaveTimer.start();
        }
    }

    Timer {
        id: leaveTimer
        interval: 400
        onTriggered: picker.effect.close()
    }

    // Highlight the nearest area in a direction (dx and dy are -1, 0 or 1), preferring areas in
    // line with the highlighted one. Up and Down stay within the columns the highlighted area
    // covers. Returns false if no area lies that way.
    function moveTowards(dx: int, dy: int): bool {
        const here = picker.drawnArea(picker.effect.current);
        const from = Qt.point(here.x + here.width / 2, here.y + here.height / 2);
        let best = -1;
        let bestScore = Infinity;
        for (let i = 0; i < picker.areas.length; ++i) {
            const there = picker.drawnArea(i);
            const to = Qt.point(there.x + there.width / 2, there.y + there.height / 2);
            const along = (to.x - from.x) * dx + (to.y - from.y) * dy;
            const besideHere = there.x < here.x + here.width && there.x + there.width > here.x;
            if (along < 0.01 || (dy !== 0 && !besideHere)) {
                continue;
            }
            const score = along + 2 * (Math.abs((to.x - from.x) * dy) + Math.abs((to.y - from.y) * dx));
            if (score < bestScore) {
                best = i;
                bestScore = score;
            }
        }
        if (best < 0) {
            return false;
        }
        picker.effect.current = best;
        return true;
    }

    focus: true

    Keys.onPressed: event => {
        const count = picker.areas.length;
        switch (event.key) {
        case Qt.Key_Escape:
            picker.effect.close();
            break;
        case Qt.Key_Tab:
            picker.effect.current = (picker.effect.current + 1) % count;
            break;
        case Qt.Key_Backtab:
            picker.effect.current = (picker.effect.current - 1 + count) % count;
            break;
        // Past the last layout, Right comes back round to the first, and Left the other way.
        case Qt.Key_Right:
            if (!picker.moveTowards(1, 0)) {
                picker.effect.current = 0;
            }
            break;
        case Qt.Key_Left:
            if (!picker.moveTowards(-1, 0)) {
                picker.effect.current = count - 1;
            }
            break;
        case Qt.Key_Down:
            picker.moveTowards(0, 1);
            break;
        case Qt.Key_Up:
            picker.moveTowards(0, -1);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            picker.effect.snap(picker.areas[picker.effect.current]);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // The windows on this screen as they were, dimmed under the picker.
    Repeater {
        model: WindowFilterModel {
            activity: Workspace.currentActivity
            desktop: Workspace.currentDesktop
            screenName: picker.screen.name
            windowModel: WindowModel {}
        }

        WindowThumbnail {
            required property var model

            wId: model.window.internalId
            x: model.window.x - picker.screen.geometry.x
            y: model.window.y - picker.screen.geometry.y
            width: model.window.width
            height: model.window.height
            z: model.window.stackingOrder
            visible: !model.window.minimized
        }
    }

    Rectangle {
        anchors.fill: parent
        z: 10000
        visible: !picker.effect.menu
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    MouseArea {
        anchors.fill: parent
        z: 10001
        hoverEnabled: true
        onClicked: picker.effect.close()
        onPositionChanged: mouse => picker.pointerAt(mouse.x, mouse.y)
    }

    Rectangle {
        id: card

        // Over the dimmed screen, near the top in the middle; as the menu, under the maximise
        // button, kept on the screen.
        x: picker.effect.menu
            ? Math.max(8, Math.min(parent.width - width - 8, Math.round(picker.maximiseButton.x + picker.maximiseButton.width / 2 - width / 2)))
            : Math.round((parent.width - width) / 2)
        y: picker.effect.menu ? Math.round(picker.maximiseButton.y + picker.maximiseButton.height + 4) : Math.round(parent.height * 0.12)
        z: 10002
        width: content.implicitWidth + Kirigami.Units.gridUnit * (picker.effect.menu ? 1 : 2)
        height: content.implicitHeight + Kirigami.Units.gridUnit * (picker.effect.menu ? 1 : 2)
        visible: picker.showsLayouts
        radius: picker.effect.menu ? 8 : Kirigami.Units.cornerRadius
        color: Kirigami.Theme.backgroundColor
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        // Clicks on the card's own background don't close the picker; the pointer over it keeps the
        // menu open.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: mouse => picker.pointerAt(card.x + mouse.x, card.y + mouse.y)
        }

        ColumnLayout {
            id: content

            anchors.centerIn: parent
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                Layout.alignment: Qt.AlignHCenter
                visible: !picker.effect.menu
                level: 3
                textFormat: Text.PlainText
                text: picker.effect.l10n.i18nc("@title", "Snap layouts")
            }

            GridLayout {
                columns: picker.columns
                rowSpacing: Kirigami.Units.gridUnit * picker.tileSpacing
                columnSpacing: Kirigami.Units.gridUnit * picker.tileSpacing

                Repeater {
                    model: picker.effect.layouts

                    LayoutTile {
                        required property var modelData
                        required property int index

                        Layout.preferredWidth: Kirigami.Units.gridUnit * picker.tileWidth * (picker.effect.menu ? 0.6 : 1)
                        Layout.preferredHeight: Kirigami.Units.gridUnit * picker.tileHeight * (picker.effect.menu ? 0.6 : 1)
                        areas: modelData
                        firstIndex: picker.firstArea(index)
                        current: picker.effect.current
                        onHighlighted: areaIndex => picker.effect.current = areaIndex
                        onChosen: area => picker.effect.snap(area)
                    }
                }
            }

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                visible: !picker.effect.menu
                text: picker.areas[picker.effect.current]?.name ?? ""
            }
        }
    }
}
