// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// Start's layout, what it shows under Recommended and the folders next to the power button. Each
// change applies to the Start menu on the taskbar at once.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property StartOptions options: StartOptions {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }

    // Settings names the page above it, so the page's own title bar would only repeat the name.
    // System Settings has no such heading, so the title bar stays there.
    Component.onCompleted: {
        if (Qt.application.name === "orielos-settings") {
            globalToolBarStyle = Kirigami.ApplicationHeaderStyle.None;
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.options.ready && !root.options.available && root.options.error.length === 0
            type: Kirigami.MessageType.Information
            text: root.l10n.i18nc("@info", "OrielOS's Start menu isn't on the taskbar, so there's nothing to change here.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.options.error.length > 0
            type: Kirigami.MessageType.Error
            text: root.options.error
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            enabled: root.options.available

            QQC2.ComboBox {
                Kirigami.FormData.label: root.l10n.i18nc("@label:listbox How Start shares its space between pinned apps and Recommended", "Layout:")
                model: [
                    root.l10n.i18nc("@item:inlistbox Start's layout", "More pins"),
                    root.l10n.i18nc("@item:inlistbox Start's layout", "Default"),
                    root.l10n.i18nc("@item:inlistbox Start's layout", "More recommendations"),
                ]
                currentIndex: root.options.layout
                onActivated: index => {
                    root.options.layout = index;
                    currentIndex = Qt.binding(() => root.options.layout);
                }
            }

            QQC2.Switch {
                Kirigami.FormData.label: root.l10n.i18nc("@title:group The Recommended section of Start", "Recommended:")
                text: root.l10n.i18nc("@option:check", "Show recently added apps")
                checked: root.options.showRecentlyAdded
                onToggled: {
                    root.options.showRecentlyAdded = checked;
                    // Follow the setting again, which shows the old value if the change fails.
                    checked = Qt.binding(() => root.options.showRecentlyAdded);
                }
            }

            QQC2.Switch {
                text: root.l10n.i18nc("@option:check", "Show recently opened files")
                checked: root.options.showRecentFiles
                onToggled: {
                    root.options.showRecentFiles = checked;
                    checked = Qt.binding(() => root.options.showRecentFiles);
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                text: root.l10n.i18nc("@info", "Apps you installed in the last few days, and the files you opened most recently, show under Recommended in Start.")
            }

            // The shortcuts next to the power button, as Windows' Folders setting offers them.
            Repeater {
                model: [
                    { id: "settings", text: root.l10n.i18nc("@option:check A shortcut next to Start's power button", "Settings") },
                    { id: "files", text: root.l10n.i18nc("@option:check A shortcut next to Start's power button", "Files") },
                    { id: "documents", text: root.l10n.i18nc("@option:check A shortcut next to Start's power button", "Documents") },
                    { id: "downloads", text: root.l10n.i18nc("@option:check A shortcut next to Start's power button", "Downloads") },
                    { id: "music", text: root.l10n.i18nc("@option:check A shortcut next to Start's power button", "Music") },
                    { id: "pictures", text: root.l10n.i18nc("@option:check A shortcut next to Start's power button", "Pictures") },
                    { id: "videos", text: root.l10n.i18nc("@option:check A shortcut next to Start's power button", "Videos") },
                    { id: "network", text: root.l10n.i18nc("@option:check A shortcut next to Start's power button", "Network") },
                    { id: "personal", text: root.l10n.i18nc("@option:check A shortcut next to Start's power button", "Personal folder") },
                ]

                delegate: QQC2.Switch {
                    id: folder

                    required property var modelData
                    required property int index

                    Kirigami.FormData.label: folder.index === 0 ? root.l10n.i18nc("@title:group", "Next to the power button:") : ""
                    text: folder.modelData.text
                    checked: root.options.folders.includes(folder.modelData.id)
                    onToggled: {
                        root.options.setFolder(folder.modelData.id, checked);
                        checked = Qt.binding(() => root.options.folders.includes(folder.modelData.id));
                    }
                }
            }
        }

        // Related settings, as Windows lists them at the foot of a page.
        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.gridUnit
            level: 4
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@title:group", "Related settings")
        }

        Repeater {
            model: [
                { page: "taskbar", text: root.l10n.i18nc("@action:button A related Settings page", "Taskbar") },
                { page: "default-apps", text: root.l10n.i18nc("@action:button A related Settings page", "Default apps") },
            ]

            delegate: Kirigami.LinkButton {
                id: related

                required property var modelData

                text: related.modelData.text
                onClicked: Qt.openUrlExternally("orielos-settings:" + related.modelData.page)
            }
        }
    }
}
