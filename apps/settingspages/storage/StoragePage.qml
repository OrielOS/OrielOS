// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// What fills the disk, as Windows' System › Storage shows it: the disk's used space, what each
// kind of file takes (each opens in Files), clean-up, and Storage Sense, which empties old Bin
// items and old temporary files by itself each day.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property StorageUsage storage: StorageUsage {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }
    // The largest part, which fills its bar; the others are drawn to scale with it.
    readonly property real largest: Math.max(1, ...root.storage.categories.map(part => Number(part.bytes)))

    function size(bytes: real): string {
        return Qt.locale().formattedDataSize(bytes, 1, Locale.DataSizeTraditionalFormat);
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
            visible: root.storage.error.length > 0
            type: Kirigami.MessageType.Error
            text: root.storage.error
        }

        Kirigami.Heading {
            level: 4
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@title:group The disk the home folder is on", "Local disk")
        }

        QQC2.ProgressBar {
            Layout.fillWidth: true
            from: 0
            to: Math.max(1, root.storage.total)
            value: root.storage.used
            Accessible.name: usedLabel.text
        }

        QQC2.Label {
            id: usedLabel

            textFormat: Text.PlainText
            text: root.l10n.i18nc("@info %1 and %2 are sizes, such as 120 GB", "%1 used of %2", root.size(root.storage.used), root.size(root.storage.total))
        }

        RowLayout {
            visible: root.storage.calculating
            spacing: Kirigami.Units.smallSpacing

            QQC2.BusyIndicator {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                running: root.storage.calculating
            }

            QQC2.Label {
                textFormat: Text.PlainText
                text: root.l10n.i18nc("@info:status", "Working out what's using space…")
                opacity: 0.75
            }
        }

        // Each kind of file, largest first, as a bar to scale.
        Repeater {
            model: root.storage.categories

            delegate: QQC2.ItemDelegate {
                id: part

                required property var modelData

                Layout.fillWidth: true
                // System and other has nowhere to open.
                enabled: part.modelData.id !== "other"
                text: String(part.modelData.name)
                Accessible.name: root.l10n.i18nc("@info:accessible %1 is a kind of file, %2 a size", "%1, %2", part.text, root.size(part.modelData.bytes))

                onClicked: root.storage.open(part.modelData.id)

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        source: String(part.modelData.icon)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true

                            QQC2.Label {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: part.text
                                elide: Text.ElideRight
                            }

                            QQC2.Label {
                                textFormat: Text.PlainText
                                text: root.size(part.modelData.bytes)
                                opacity: 0.75
                            }
                        }

                        QQC2.ProgressBar {
                            Layout.fillWidth: true
                            from: 0
                            to: root.largest
                            value: Number(part.modelData.bytes)
                        }
                    }
                }
            }
        }

        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.gridUnit
            level: 4
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@title:group", "Clean-up recommendations")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            QQC2.Label {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: root.l10n.i18nc("@info %1 is a size", "Temporary files and the Bin take %1.", root.size(root.storage.temporaryBytes + root.storage.binBytes))
            }

            QQC2.Button {
                text: root.l10n.i18nc("@action:button", "Clean up now…")
                icon.name: "edit-clear-history"
                enabled: !root.storage.cleaning && !root.storage.calculating
                onClicked: confirmCleanUp.open()
            }
        }

        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.gridUnit
            level: 4
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@title:group", "Storage management")
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.Switch {
                id: sense

                Kirigami.FormData.label: root.l10n.i18nc("@option:check", "Storage Sense:")
                text: root.storage.senseEnabled ? root.l10n.i18nc("@option:check A switch's state", "On") : root.l10n.i18nc("@option:check A switch's state", "Off")
                checked: root.storage.senseEnabled
                onToggled: {
                    root.storage.senseEnabled = checked;
                    checked = Qt.binding(() => root.storage.senseEnabled);
                }
            }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                opacity: 0.75
                text: root.l10n.i18nc("@info", "Once a day, delete temporary files that apps haven't used for 30 days and empty old items from the Bin.")
            }

            QQC2.ComboBox {
                id: binAge

                readonly property list<int> days: [0, 1, 14, 30, 60]

                Kirigami.FormData.label: root.l10n.i18nc("@label:listbox", "Delete files in my Bin if they've been there for over:")
                enabled: root.storage.senseEnabled
                model: [
                    root.l10n.i18nc("@item:inlistbox Never delete files in the Bin", "Never"),
                    root.l10n.i18ncp("@item:inlistbox", "%1 day", "%1 days", 1),
                    root.l10n.i18ncp("@item:inlistbox", "%1 day", "%1 days", 14),
                    root.l10n.i18ncp("@item:inlistbox", "%1 day", "%1 days", 30),
                    root.l10n.i18ncp("@item:inlistbox", "%1 day", "%1 days", 60),
                ]
                currentIndex: Math.max(0, binAge.days.indexOf(root.storage.binDays))
                onActivated: index => {
                    root.storage.binDays = binAge.days[index];
                    currentIndex = Qt.binding(() => Math.max(0, binAge.days.indexOf(root.storage.binDays)));
                }
            }

            QQC2.Button {
                text: root.l10n.i18nc("@action:button", "Run Storage Sense now")
                enabled: root.storage.senseEnabled && !root.storage.cleaning
                onClicked: root.storage.cleanUp(false)
            }
        }

        // Related settings, as Windows lists them at the foot of a page.
        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.gridUnit
            level: 4
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@title:group", "Related settings")
        }

        Kirigami.LinkButton {
            text: root.l10n.i18nc("@action:button A related Settings page", "Installed apps")
            onClicked: Qt.openUrlExternally("orielos-settings:apps")
        }
    }

    Kirigami.PromptDialog {
        id: confirmCleanUp

        title: root.l10n.i18nc("@title:window", "Clean up now?")
        subtitle: root.l10n.i18nc("@info", "This empties the Bin and deletes thumbnails and the temporary files that apps haven't used for 30 days. Files in the Bin can't be restored afterwards.")
        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action {
                text: root.l10n.i18nc("@action:button", "Clean up")
                icon.name: "edit-clear-history"
                onTriggered: {
                    root.storage.cleanUp(true);
                    confirmCleanUp.close();
                }
            },
            Kirigami.Action {
                text: root.l10n.i18nc("@action:button", "Cancel")
                icon.name: "dialog-cancel"
                onTriggered: confirmCleanUp.close()
            }
        ]
    }
}
