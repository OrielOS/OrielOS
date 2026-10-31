// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// One screen while snap assist shows: its windows as they are, and on the snapped window's screen,
// over the free half, the other windows to choose from as thumbnails with their icon and title.
// The arrow keys and Tab move between them, Enter or a click snaps one, Escape or a click elsewhere
// closes.

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kwin

FocusScope {
    id: assist

    // The scene effect in main.qml, and the screen this copy is on.
    readonly property var effect: SceneView.effect
    readonly property var screen: SceneView.screen
    readonly property bool offers: assist.effect.snapped !== null && assist.effect.snapped.output === assist.screen
    // The free half, in this screen's coordinates.
    readonly property rect free: {
        if (!assist.offers) {
            return Qt.rect(0, 0, 0, 0);
        }
        const area = Workspace.clientArea(Workspace.MaximizeArea, assist.effect.snapped);
        const half = Math.round(area.width / 2);
        return Qt.rect(area.x - assist.screen.geometry.x + (assist.effect.freeSide === "right" ? area.width - half : 0),
            area.y - assist.screen.geometry.y, half, area.height);
    }
    property int current: 0

    focus: true

    Keys.onPressed: event => {
        const count = assist.effect.candidates.length;
        switch (event.key) {
        case Qt.Key_Escape:
            assist.effect.close();
            break;
        case Qt.Key_Tab:
        case Qt.Key_Right:
        case Qt.Key_Down:
            assist.current = (assist.current + 1) % Math.max(1, count);
            break;
        case Qt.Key_Backtab:
        case Qt.Key_Left:
        case Qt.Key_Up:
            assist.current = (assist.current - 1 + count) % Math.max(1, count);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            assist.effect.choose(assist.effect.candidates[assist.current]);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // The screen as it was: its windows where they are.
    Repeater {
        model: WindowFilterModel {
            activity: Workspace.currentActivity
            desktop: Workspace.currentDesktop
            screenName: assist.screen.name
            windowModel: WindowModel {}
        }

        WindowThumbnail {
            required property var model

            wId: model.window.internalId
            x: model.window.x - assist.screen.geometry.x
            y: model.window.y - assist.screen.geometry.y
            width: model.window.width
            height: model.window.height
            z: model.window.stackingOrder
            visible: !model.window.minimized
        }
    }

    // Anywhere but a window offered closes.
    MouseArea {
        anchors.fill: parent
        z: 10000
        onClicked: assist.effect.close()
    }

    // The free half: Sill's glass over the desktop, with the windows on it.
    Rectangle {
        id: half

        x: assist.free.x + 6
        y: assist.free.y + 6
        width: assist.free.width - 12
        height: assist.free.height - 12
        z: 10001
        visible: assist.offers
        radius: 8
        color: Qt.rgba(12 / 255, 21 / 255, 48 / 255, 0.9)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        // A grid as close to square as the windows allow, each cell a little wider than tall.
        readonly property int count: assist.effect.candidates.length
        readonly property int columns: Math.max(1, Math.ceil(Math.sqrt(count * width / height / 1.6)))
        readonly property int rows: Math.max(1, Math.ceil(count / columns))
        readonly property real cellWidth: (width - 48) / columns
        readonly property real cellHeight: Math.min((height - 48) / rows, cellWidth * 0.8)

        MouseArea {
            // Clicks between the windows don't close.
            anchors.fill: parent
        }

        Grid {
            anchors.centerIn: parent
            columns: half.columns
            spacing: 0

            Repeater {
                model: assist.effect.candidates

                delegate: Item {
                    id: cell

                    required property var modelData
                    required property int index
                    readonly property bool highlighted: assist.current === cell.index || choice.containsMouse

                    width: half.cellWidth
                    height: half.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 6
                        radius: 8
                        color: cell.highlighted ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                        border.width: assist.current === cell.index ? 2 : 0
                        border.color: Kirigami.Theme.highlightColor
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Kirigami.Icon {
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                source: cell.modelData.icon
                            }
                            Text {
                                Layout.fillWidth: true
                                text: cell.modelData.caption
                                color: "#FFFFFF"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }

                        WindowThumbnail {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            wId: cell.modelData.internalId
                        }
                    }

                    MouseArea {
                        id: choice

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: assist.effect.choose(cell.modelData)
                    }
                }
            }
        }
    }

    Connections {
        target: assist.effect
        function onVisibleChanged() {
            assist.current = 0;
        }
    }
}
