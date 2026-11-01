// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// One screen while the switcher shows: dimmed, and on the active screen the pane of thumbnails,
// drawn as Alt+Tab's (plasma/kwin/switcher/contents/ui/Thumbnails.qml).

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kwin
import org.kde.plasma.components as PC3

FocusScope {
    id: root

    readonly property var effect: SceneView.effect
    readonly property var screen: SceneView.screen
    readonly property bool showsPane: root.screen === Workspace.activeScreen

    // Sill's thumbnails: 240 px wide in the screen's shape, with a line for the icon and title.
    readonly property real screenRatio: root.screen.geometry.width / Math.max(1, root.screen.geometry.height)
    readonly property int thumbnailWidth: 240
    readonly property int thumbnailHeight: Math.round(thumbnailWidth / screenRatio)
    readonly property int captionHeight: 28
    readonly property int padding: 8
    readonly property int cellWidth: thumbnailWidth + 2 * padding
    readonly property int cellHeight: captionHeight + thumbnailHeight + 2 * padding
    readonly property int columns: Math.max(1, Math.min(grid.count, Math.floor(width * 0.9 / cellWidth)))
    readonly property int rows: Math.ceil(grid.count / columns)

    focus: true

    // The desktop and its windows as they were, dimmed under the pane; a scene effect draws the
    // whole screen itself.
    Repeater {
        model: WindowFilterModel {
            activity: Workspace.currentActivity
            desktop: Workspace.currentDesktop
            screenName: root.screen.name
            windowModel: WindowModel {}
        }

        WindowThumbnail {
            required property var model

            wId: model.window.internalId
            x: model.window.x - root.screen.geometry.x
            y: model.window.y - root.screen.geometry.y
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

    // A click beside the pane closes the switcher.
    MouseArea {
        anchors.fill: parent
        z: 10001
        onClicked: root.effect.close()
    }

    Rectangle {
        id: pane

        anchors.centerIn: parent
        z: 10002
        visible: root.showsPane
        width: Math.max(root.cellWidth, root.columns * root.cellWidth) + 24
        height: Math.min(root.height * 0.8, Math.max(root.cellHeight, root.rows * root.cellHeight)) + 24
        radius: 8
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.94)
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.13)

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        // Clicks on the pane stay there.
        MouseArea {
            anchors.fill: parent
        }

        GridView {
            id: grid

            anchors.fill: parent
            anchors.margins: 12
            clip: true
            model: root.effect.windows
            currentIndex: root.effect.current
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false

            delegate: MouseArea {
                id: cell

                required property int index
                required property var modelData

                width: grid.cellWidth
                height: grid.cellHeight
                hoverEnabled: true
                Accessible.name: cell.modelData.caption
                Accessible.role: Accessible.ListItem

                onClicked: root.effect.activate(cell.index)

                // Selected: the highlight colour around it; hovered: a faint fill.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 8
                    color: cell.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06) : "transparent"
                    border.width: cell.GridView.isCurrentItem ? 3 : 0
                    border.color: Kirigami.Theme.highlightColor
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.padding
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.captionHeight
                        spacing: 8

                        Kirigami.Icon {
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            source: cell.modelData.icon
                        }

                        PC3.Label {
                            Layout.fillWidth: true
                            text: cell.modelData.caption
                            textFormat: Text.PlainText
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        PC3.ToolButton {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            visible: cell.modelData.closeable && cell.containsMouse
                            icon.name: "window-close-symbolic"
                            icon.width: 12
                            icon.height: 12
                            display: PC3.AbstractButton.IconOnly
                            text: i18ndc("kwin", "@action:button", "Close")
                            onClicked: root.effect.closeWindow(cell.index)
                        }
                    }

                    // The thumbnail, letterboxed in the screen's shape.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        WindowThumbnail {
                            anchors.fill: parent
                            wId: cell.modelData.internalId
                        }
                    }
                }
            }
        }

        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - 32
            visible: grid.count === 0
            icon.source: "edit-none"
            text: i18ndc("kwin", "@info:placeholder no entries in the task switcher", "No open windows")
        }
    }

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Left:
            root.effect.move(-1);
            break;
        case Qt.Key_Right:
        case Qt.Key_Tab:
            root.effect.move(1);
            break;
        case Qt.Key_Backtab:
            root.effect.move(-1);
            break;
        case Qt.Key_Up:
            root.effect.move(-root.columns);
            break;
        case Qt.Key_Down:
            root.effect.move(root.columns);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.effect.activate(root.effect.current);
            break;
        case Qt.Key_Delete:
            root.effect.closeWindow(root.effect.current);
            break;
        case Qt.Key_Escape:
            root.effect.close();
            break;
        default:
            return;
        }
        event.accepted = true;
    }
}
