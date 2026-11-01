// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// Settings › Apps › Installed apps, as Windows' page: the apps from the Store with their version,
// size and install date, sorted and searched, each with Modify (its Store page) and Uninstall; and
// where apps may come from.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property InstalledApps installed: InstalledApps {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }
    readonly property var shown: {
        const words = search.text.trim().toLowerCase();
        const apps = root.installed.apps.filter(app => words.length === 0 || app.name.toLowerCase().includes(words) || app.id.toLowerCase().includes(words));
        if (sortBy.currentIndex === 1) {
            apps.sort((a, b) => b.installedAt - a.installedAt);
        }
        return apps;
    }
    property var pendingUninstall: null

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.installed.error.length > 0
            type: Kirigami.MessageType.Error
            text: root.installed.error
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.SearchField {
                id: search

                Layout.fillWidth: true
                placeholderText: root.l10n.i18nc("@info:placeholder", "Search apps")
            }

            QQC2.ComboBox {
                id: sortBy

                model: [root.l10n.i18nc("@item:inlistbox Sort apps by", "Name"), root.l10n.i18nc("@item:inlistbox Sort apps by", "Install date")]
                Accessible.name: root.l10n.i18nc("@label:listbox", "Sort by")
            }
        }

        QQC2.Label {
            text: root.l10n.i18ncp("@info", "%1 app found", "%1 apps found", root.shown.length)
            color: Kirigami.Theme.disabledTextColor
        }

        Repeater {
            model: root.shown

            delegate: Kirigami.AbstractCard {
                id: card

                required property var modelData

                Layout.fillWidth: true
                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                        source: card.modelData.id
                        fallback: "application-x-executable"
                        Accessible.ignored: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        QQC2.Label {
                            Layout.fillWidth: true
                            text: card.modelData.name
                            elide: Text.ElideRight
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            text: [card.modelData.version, card.modelData.installedOn].filter(part => part.length > 0).join("  ·  ")
                            color: Kirigami.Theme.disabledTextColor
                            font: Kirigami.Theme.smallFont
                            elide: Text.ElideRight
                        }
                    }

                    QQC2.Label {
                        text: card.modelData.size
                        color: Kirigami.Theme.disabledTextColor
                    }

                    QQC2.ToolButton {
                        icon.name: "overflow-menu"
                        text: root.l10n.i18nc("@action:button", "More options for %1", card.modelData.name)
                        display: QQC2.AbstractButton.IconOnly
                        enabled: !root.installed.busy
                        onClicked: appMenu.popup()

                        QQC2.Menu {
                            id: appMenu

                            QQC2.MenuItem {
                                text: root.l10n.i18nc("@action:inmenu", "Modify")
                                icon.name: "document-edit"
                                onTriggered: Qt.openUrlExternally("appstream://" + card.modelData.id)
                            }

                            QQC2.MenuItem {
                                text: root.l10n.i18nc("@action:inmenu", "Uninstall")
                                icon.name: "edit-delete"
                                onTriggered: {
                                    root.pendingUninstall = card.modelData;
                                    uninstallDialog.open();
                                }
                            }
                        }
                    }
                }
            }
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: root.l10n.i18nc("@title:group", "Where apps can come from")
            }

            QQC2.ComboBox {
                model: [root.l10n.i18nc("@item:inlistbox", "Anywhere"), root.l10n.i18nc("@item:inlistbox", "Anywhere, with the Store suggested first"),
                    root.l10n.i18nc("@item:inlistbox", "The Store only")]
                currentIndex: root.installed.appSource
                Accessible.name: root.l10n.i18nc("@label:listbox", "Where apps can come from")
                onActivated: index => {
                    root.installed.setAppSource(index);
                    currentIndex = Qt.binding(() => root.installed.appSource);
                }
            }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                text: root.l10n.i18nc("@info", "Apps from the Store are checked and update by themselves. Windows programs you download (.exe and .msi files) run through Run this app unless you choose the Store only.")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
            }
        }
    }

    Kirigami.PromptDialog {
        id: uninstallDialog

        title: root.l10n.i18nc("@title:dialog", "Uninstall %1", root.pendingUninstall ? root.pendingUninstall.name : "")
        subtitle: root.l10n.i18nc("@info", "It is removed from this computer. Its settings and files in your home folder stay, in case you install it again.")
        standardButtons: QQC2.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action {
                text: root.l10n.i18nc("@action:button", "Uninstall")
                icon.name: "edit-delete"
                onTriggered: {
                    root.installed.uninstall(root.pendingUninstall.id);
                    uninstallDialog.close();
                }
            },
            Kirigami.Action {
                text: root.l10n.i18nc("@action:button", "Cancel")
                icon.name: "dialog-cancel"
                onTriggered: uninstallDialog.close()
            }
        ]
    }
}
