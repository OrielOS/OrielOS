// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// One screen while the picker shows: its windows, dimmed, and on the active window's screen the
// layouts. Arrow keys or Tab move between areas, Enter or Space snaps, Escape or a click
// elsewhere closes.

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
    property int current: 0

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

    // Move to the first area of the next or previous layout.
    function moveLayout(step: int) {
        const count = picker.effect.layouts.length;
        picker.current = picker.firstArea((picker.layoutOf(picker.current) + step + count) % count);
    }

    focus: true

    Keys.onPressed: event => {
        const count = picker.areas.length;
        switch (event.key) {
        case Qt.Key_Escape:
            picker.effect.close();
            break;
        case Qt.Key_Right:
        case Qt.Key_Tab:
            picker.current = (picker.current + 1) % count;
            break;
        case Qt.Key_Left:
        case Qt.Key_Backtab:
            picker.current = (picker.current - 1 + count) % count;
            break;
        case Qt.Key_Down:
            picker.moveLayout(1);
            break;
        case Qt.Key_Up:
            picker.moveLayout(-1);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            picker.effect.snap(picker.areas[picker.current]);
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
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    MouseArea {
        anchors.fill: parent
        z: 10001
        onClicked: picker.effect.close()
    }

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.12)
        z: 10002
        width: content.implicitWidth + Kirigami.Units.gridUnit * 2
        height: content.implicitHeight + Kirigami.Units.gridUnit * 2
        visible: picker.showsLayouts
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.backgroundColor
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        // Clicks on the card's own background don't close the picker.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: content

            anchors.centerIn: parent
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                Layout.alignment: Qt.AlignHCenter
                level: 3
                textFormat: Text.PlainText
                text: picker.effect.l10n.i18nc("@title", "Snap layouts")
            }

            RowLayout {
                spacing: Kirigami.Units.gridUnit

                Repeater {
                    model: picker.effect.layouts

                    LayoutTile {
                        required property var modelData
                        required property int index

                        areas: modelData
                        firstIndex: picker.firstArea(index)
                        current: picker.current
                        onHighlighted: areaIndex => picker.current = areaIndex
                        onChosen: area => picker.effect.snap(area)
                    }
                }
            }

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                text: picker.areas[picker.current]?.name ?? ""
            }
        }
    }
}
