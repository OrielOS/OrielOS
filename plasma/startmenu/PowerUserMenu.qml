// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.core as PlasmaCore

// Windows' power user menu, above the Start button: Win+X or a right-click on Start opens it. Each
// item has an underlined access key, so Win+X then a letter opens it; U opens Shut down or sign
// out, whose own letters then choose. The applet class runs the chosen item.
PlasmaCore.Dialog {
    id: menu

    // Which item was chosen, by its id: see startapplet.cpp.
    signal chosen(string id)

    property bool open: false
    property bool powerOpen: false

    readonly property var items: [
        { id: "apps", text: KI18n.i18nc("@action:inmenu Power user menu", "Installed a&pps") },
        { id: "power", text: KI18n.i18nc("@action:inmenu Power user menu", "P&ower options") },
        { id: "system", text: KI18n.i18nc("@action:inmenu Power user menu", "S&ystem") },
        { id: "devices", text: KI18n.i18nc("@action:inmenu Power user menu", "Device &Manager") },
        { id: "network", text: KI18n.i18nc("@action:inmenu Power user menu", "Net&work connections") },
        { separator: true },
        { id: "terminal", text: KI18n.i18nc("@action:inmenu Power user menu", "Term&inal") },
        { id: "admin-terminal", text: KI18n.i18nc("@action:inmenu Power user menu", "Terminal (&Admin)") },
        { separator: true },
        { id: "process-manager", text: KI18n.i18nc("@action:inmenu Power user menu", "Pro&cess Manager") },
        { id: "settings", text: KI18n.i18nc("@action:inmenu Power user menu", "Setti&ngs") },
        { id: "files", text: KI18n.i18nc("@action:inmenu Power user menu", "Fil&es") },
        { id: "search", text: KI18n.i18nc("@action:inmenu Power user menu", "&Search") },
        { id: "run", text: KI18n.i18nc("@action:inmenu Power user menu", "&Run") },
        { separator: true },
        { id: "power-menu", text: KI18n.i18nc("@action:inmenu Power user menu", "Sh&ut down or sign out"), submenu: true },
        { id: "sign-out", text: KI18n.i18nc("@action:inmenu Shut down or sign out", "S&ign out"), inSubmenu: true },
        { id: "sleep", text: KI18n.i18nc("@action:inmenu Shut down or sign out", "&Sleep"), inSubmenu: true },
        { id: "shut-down", text: KI18n.i18nc("@action:inmenu Shut down or sign out", "Sh&ut down"), inSubmenu: true },
        { id: "restart", text: KI18n.i18nc("@action:inmenu Shut down or sign out", "&Restart"), inSubmenu: true },
        { id: "desktop", text: KI18n.i18nc("@action:inmenu Power user menu", "&Desktop") },
    ]

    // An item's access key, and its label with that letter underlined.
    function accessKey(text: string): string {
        const at = text.indexOf("&");
        return at >= 0 && at + 1 < text.length ? text.charAt(at + 1).toLowerCase() : "";
    }
    function styled(text: string): string {
        const at = text.indexOf("&");
        const plain = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
        return at < 0 ? plain(text) : plain(text.slice(0, at)) + "<u>" + plain(text.charAt(at + 1)) + "</u>" + plain(text.slice(at + 2));
    }

    function choose(item) {
        if (item.submenu) {
            menu.powerOpen = !menu.powerOpen;
            return;
        }
        menu.open = false;
        menu.chosen(item.id);
    }

    location: PlasmaCore.Types.BottomEdge
    type: PlasmaCore.Dialog.PopupMenu
    flags: Qt.WindowStaysOnTopHint
    hideOnWindowDeactivate: true
    visible: menu.open

    onVisibleChanged: {
        if (visible) {
            menu.powerOpen = false;
            menu.requestActivate();
            list.forceActiveFocus();
        } else {
            menu.open = false;
        }
    }

    mainItem: FocusScope {
        implicitWidth: list.implicitWidth
        implicitHeight: list.implicitHeight

        Keys.onEscapePressed: menu.open = false
        Keys.onPressed: event => {
            const key = event.text.toLowerCase();
            if (key.length !== 1) {
                return;
            }
            // In Shut down or sign out, its own letters choose; elsewhere the menu's do.
            const match = menu.items.find(item => !item.separator && !!item.inSubmenu === menu.powerOpen && menu.accessKey(item.text) === key);
            if (match) {
                menu.choose(match);
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: list

            focus: true
            spacing: 0

            Repeater {
                model: menu.items

                delegate: Loader {
                    id: row

                    required property var modelData

                    Layout.fillWidth: true
                    visible: !row.modelData.inSubmenu || menu.powerOpen
                    sourceComponent: row.modelData.separator ? separator : entry

                    Component {
                        id: separator

                        Rectangle {
                            implicitHeight: 9
                            color: "transparent"

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 1
                                color: Kirigami.Theme.textColor
                                opacity: 0.12
                            }
                        }
                    }

                    Component {
                        id: entry

                        MouseArea {
                            id: area

                            implicitWidth: Math.max(220, label.implicitWidth + 48)
                            implicitHeight: 30
                            hoverEnabled: true
                            Accessible.role: row.modelData.submenu ? Accessible.ButtonMenu : Accessible.MenuItem
                            Accessible.name: row.modelData.text.replace("&", "")
                            onClicked: menu.choose(row.modelData)

                            Rectangle {
                                anchors.fill: parent
                                radius: 4
                                color: Kirigami.Theme.textColor
                                opacity: area.containsMouse ? 0.08 : 0
                            }

                            PC3.Label {
                                id: label
                                anchors.left: parent.left
                                anchors.leftMargin: row.modelData.inSubmenu ? 28 : 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: menu.styled(row.modelData.text)
                                textFormat: Text.StyledText
                                font.pixelSize: 13
                            }

                            Kirigami.Icon {
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12
                                height: 12
                                visible: !!row.modelData.submenu
                                source: menu.powerOpen ? "go-up" : "go-down"
                            }
                        }
                    }
                }
            }
        }
    }
}
