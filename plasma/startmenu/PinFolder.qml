// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// An open folder of pins, over the pinned apps as in Windows: its name, which can be changed, and
// its apps, which open with a click. Right-clicking an app offers Move out of folder. Escape, or a
// click beside the apps, closes it.

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Item {
    id: folderView

    required property MenuState menu

    readonly property var folder: menu.pinnedEntries.find(entry => entry.folder && entry.key === folderView.menu.openFolder) ?? null
    readonly property GridView view: apps

    visible: !!folderView.folder

    onFolderChanged: {
        if (folderView.folder) {
            apps.currentIndex = 0;
            apps.forceActiveFocus(Qt.OtherFocusReason);
        }
    }

    // A click beside the folder closes it. No click reaches the pins underneath.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: folderView.menu.openFolder = ""
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)

        // Clicks inside the folder stay there.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            PC3.TextField {
                id: name

                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                horizontalAlignment: TextInput.AlignHCenter
                text: String(folderView.folder?.name ?? "")
                Accessible.name: KI18n.i18nc("@label:textbox", "Folder name")
                // Plain text with no frame until it's being changed, as Windows' folder name.
                background: Rectangle {
                    radius: 4
                    color: name.activeFocus ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : "transparent"
                    border.width: name.activeFocus ? 1 : 0
                    border.color: Kirigami.Theme.highlightColor
                }

                onEditingFinished: {
                    if (folderView.folder && name.text !== folderView.folder.name) {
                        folderView.menu.renameFolder(folderView.folder.key, name.text);
                    }
                }
                Keys.onEscapePressed: {
                    name.text = String(folderView.folder?.name ?? "");
                    apps.forceActiveFocus(Qt.OtherFocusReason);
                }
                Keys.onDownPressed: apps.forceActiveFocus(Qt.TabFocusReason)
            }

            GridView {
                id: apps

                readonly property int columns: folderView.menu.pinnedColumns

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: folderView.folder?.apps ?? []
                cellWidth: Math.floor(width / columns)
                // Pinned's tile: room for a 38 px icon and two lines of the app's name.
                cellHeight: 84 + Kirigami.Units.smallSpacing
                keyNavigationEnabled: false
                currentIndex: 0

                Accessible.name: String(folderView.folder?.name ?? "")
                Accessible.role: Accessible.List

                delegate: AppTile {
                    id: tile

                    required property int index
                    required property var modelData

                    width: apps.cellWidth
                    height: apps.cellHeight
                    label: String(folderView.menu.folderAppsModel.data(folderView.menu.folderAppsModel.index(tile.modelData.row, 0), Qt.DisplayRole) ?? "")
                    iconSource: folderView.menu.folderAppsModel.data(folderView.menu.folderAppsModel.index(tile.modelData.row, 0), Qt.DecorationRole) ?? ""
                    current: GridView.isCurrentItem && apps.activeFocus

                    onClicked: folderView.menu.launchFolderApp(tile.modelData.row)
                    onContextMenuRequested: (x, y) => folderView.menu.openFolderAppMenu(folderView.folder.key, tile.modelData, tile, x, y, false)
                }

                Keys.onPressed: event => {
                    const index = apps.currentIndex;
                    if (folderView.menu.isContextMenuKey(event)) {
                        if (apps.currentItem) {
                            folderView.menu.openFolderAppMenu(folderView.folder.key, folderView.folder.apps[index], apps.currentItem, apps.currentItem.width / 2,
                                apps.currentItem.height / 2, true);
                        }
                        event.accepted = true;
                        return;
                    }
                    const count = apps.count;
                    const mirrored = apps.effectiveLayoutDirection === Qt.RightToLeft;
                    switch (event.key) {
                    case Qt.Key_Escape:
                        folderView.menu.openFolder = "";
                        folderView.menu.focusPinned();
                        event.accepted = true;
                        break;
                    case Qt.Key_Left:
                    case Qt.Key_Right: {
                        const step = (event.key === Qt.Key_Right) !== mirrored ? 1 : -1;
                        apps.currentIndex = Math.max(0, Math.min(count - 1, index + step));
                        event.accepted = true;
                        break;
                    }
                    case Qt.Key_Up:
                        if (index >= apps.columns) {
                            apps.currentIndex = index - apps.columns;
                        } else {
                            name.forceActiveFocus(Qt.BacktabFocusReason);
                        }
                        event.accepted = true;
                        break;
                    case Qt.Key_Down:
                        apps.currentIndex = Math.min(count - 1, index + apps.columns);
                        event.accepted = true;
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                    case Qt.Key_Space:
                        if (index >= 0) {
                            folderView.menu.launchFolderApp(folderView.folder.apps[index].row);
                        }
                        event.accepted = true;
                        break;
                    }
                }
            }
        }
    }
}
