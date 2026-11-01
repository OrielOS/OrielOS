// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWin
import org.kde.plasma.components as PC3

// The whole screen while Alt+Tab shows: a dim over it, and the pane of thumbnails in the middle.
FocusScope {
    id: root

    required property var switcher

    // Sill's thumbnails: 240 px wide in the screen's shape, with a line for the icon and title.
    readonly property real screenRatio: root.switcher.screenGeometry.width / Math.max(1, root.switcher.screenGeometry.height)
    readonly property int thumbnailWidth: 240
    readonly property int thumbnailHeight: Math.round(thumbnailWidth / screenRatio)
    readonly property int captionHeight: 28
    readonly property int padding: 8
    readonly property int cellWidth: thumbnailWidth + 2 * padding
    readonly property int cellHeight: captionHeight + thumbnailHeight + 2 * padding
    readonly property int columns: Math.max(1, Math.min(grid.count, Math.floor(width * 0.9 / cellWidth)))
    readonly property int rows: Math.ceil(grid.count / columns)

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    Rectangle {
        id: pane

        anchors.centerIn: parent
        width: Math.max(root.cellWidth, root.columns * root.cellWidth) + 24
        height: Math.min(root.height * 0.8, Math.max(root.cellHeight, root.rows * root.cellHeight)) + 24
        radius: 8
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.94)
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.13)

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        GridView {
            id: grid

            anchors.fill: parent
            anchors.margins: 12
            clip: true
            focus: true
            model: root.switcher.model
            currentIndex: root.switcher.currentIndex
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            keyNavigationWraps: true
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds

            onCurrentIndexChanged: root.switcher.currentIndex = grid.currentIndex

            delegate: MouseArea {
                id: cell

                required property int index
                required property var model

                width: grid.cellWidth
                height: grid.cellHeight
                hoverEnabled: true
                Accessible.name: cell.model.caption
                Accessible.role: Accessible.ListItem

                onClicked: root.switcher.model.activate(cell.index)

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
                            source: cell.model.icon
                        }

                        PC3.Label {
                            Layout.fillWidth: true
                            text: cell.model.caption
                            textFormat: Text.PlainText
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        PC3.ToolButton {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            visible: cell.model.closeable && cell.containsMouse
                            icon.name: "window-close-symbolic"
                            icon.width: 12
                            icon.height: 12
                            display: PC3.AbstractButton.IconOnly
                            text: i18ndc("kwin", "@action:button", "Close")
                            onClicked: root.switcher.model.close(cell.index)
                        }
                    }

                    // The thumbnail, letterboxed in the screen's shape.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        KWin.WindowThumbnail {
                            anchors.fill: parent
                            wId: cell.model.windowId
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
            grid.moveCurrentIndexLeft();
            break;
        case Qt.Key_Right:
            grid.moveCurrentIndexRight();
            break;
        case Qt.Key_Up:
            grid.moveCurrentIndexUp();
            break;
        case Qt.Key_Down:
            grid.moveCurrentIndexDown();
            break;
        case Qt.Key_Delete:
            if (grid.currentIndex >= 0) {
                root.switcher.model.close(grid.currentIndex);
            }
            break;
        default:
            return;
        }
        event.accepted = true;
    }
}
