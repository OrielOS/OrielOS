// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// Recovery: Reset this PC. Two choices, each with one button and a question before anything
// happens; while a reset is being got ready, its progress and Cancel take their place, and once it's
// ready, Restart now.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property ResetPC reset: ResetPC {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }
    readonly property bool choosing: !root.reset.working && !root.reset.ready

    // Asks before the reset starts or is cancelled. Cancel takes the focus when it opens, so a key
    // press never confirms by accident. The buttons are plain buttons rather than actions, so the
    // mnemonic in their text works.
    component Question: Kirigami.PromptDialog {
        id: question

        required property string actionText
        required property string actionIcon
        required property string cancelText
        property bool destructive: false

        signal confirmed

        // Without it nothing in the popup can take the keyboard focus, and Esc doesn't reach it.
        focus: true
        standardButtons: QQC2.Dialog.NoButton
        footer: QQC2.DialogButtonBox {
            leftPadding: Kirigami.Units.largeSpacing
            rightPadding: Kirigami.Units.largeSpacing
            bottomPadding: Kirigami.Units.largeSpacing
            topPadding: Kirigami.Units.smallSpacing

            onAccepted: {
                question.close();
                question.confirmed();
            }
            onRejected: question.close()

            QQC2.Button {
                id: keepButton

                QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.RejectRole
                text: question.cancelText
                icon.name: "dialog-cancel"
            }

            QQC2.Button {
                QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.AcceptRole
                text: question.actionText
                icon.name: question.actionIcon
                icon.color: question.destructive ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            }
        }

        onOpened: keepButton.forceActiveFocus()
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

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 3
            text: root.l10n.i18nc("@title:group", "Reset this PC")
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.l10n.i18nc("@info",
                "If OrielOS isn't working as it should, a reset puts the newest version back on this PC, with its own settings. It downloads about 4 GB. Only OrielOS's own part of the drive changes: Windows, other drives and anything else on this one stay as they are.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: text.length > 0
            type: Kirigami.MessageType.Error
            text: root.reset.error
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.choosing && text.length > 0
            type: root.reset.outcomeIsError ? Kirigami.MessageType.Warning : Kirigami.MessageType.Information
            text: root.reset.outcome
        }

        // The two choices.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            visible: root.choosing
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                Layout.alignment: Qt.AlignTop
                source: "folder-documents"
                Accessible.ignored: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: root.l10n.i18nc("@title", "Reset and keep files")
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.l10n.i18nc("@info",
                        "Accounts, passwords and everything in each person's home folder stay, games included. System settings go back to how OrielOS starts, apart from this PC's name, language, keyboard, time zone and saved networks. Apps from the Store are removed, and Firefox comes back.")
                }
            }

            QQC2.Button {
                Layout.alignment: Qt.AlignTop
                text: root.l10n.i18nc("@action:button", "&Reset…")
                icon.name: "edit-reset"
                enabled: !root.reset.busy
                onClicked: keepDialog.open()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.choosing
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                Layout.alignment: Qt.AlignTop
                source: "edit-clear-all"
                Accessible.ignored: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: root.l10n.i18nc("@title", "Reset and remove everything")
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.l10n.i18nc("@info",
                        "Every account, and every file and app in them, is removed. This PC then starts with first-run setup, as after installing OrielOS. The drive isn't securely erased, so before giving this PC away, use a tool made for that.")
                }
            }

            QQC2.Button {
                Layout.alignment: Qt.AlignTop
                text: root.l10n.i18nc("@action:button", "Remove &everything…")
                icon.name: "edit-delete"
                enabled: !root.reset.busy
                onClicked: eraseDialog.open()
            }
        }

        // Getting the reset ready.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            visible: root.reset.working
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.reset.status
            }

            QQC2.ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: 1
                indeterminate: root.reset.progress < 0
                value: Math.max(0, root.reset.progress)
                Accessible.name: root.reset.status
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: text.length > 0
                color: Kirigami.Theme.disabledTextColor
                text: root.reset.progressText
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.l10n.i18nc("@info", "You can keep using this PC meanwhile. Nothing changes until you restart.")
            }

            QQC2.Button {
                Layout.topMargin: Kirigami.Units.smallSpacing
                text: root.l10n.i18nc("@action:button", "C&ancel the reset")
                icon.name: "dialog-cancel"
                enabled: !root.reset.busy
                onClicked: root.reset.cancel()
            }
        }

        // Ready for the restart.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            visible: root.reset.ready
            spacing: Kirigami.Units.largeSpacing

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                type: root.reset.keepsFiles ? Kirigami.MessageType.Information : Kirigami.MessageType.Warning
                text: root.reset.status
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: root.l10n.i18nc("@action:button", "Restart &now")
                    icon.name: "system-reboot"
                    onClicked: root.reset.restart()
                }

                QQC2.Button {
                    text: root.l10n.i18nc("@action:button", "C&ancel the reset")
                    icon.name: "dialog-cancel"
                    enabled: !root.reset.busy
                    onClicked: root.reset.cancel()
                }
            }
        }
    }

    Question {
        id: keepDialog

        title: root.l10n.i18nc("@title:dialog", "Reset this PC and keep files?")
        subtitle: root.l10n.i18nc("@info",
            "OrielOS downloads its newest version and gets it ready; you then restart to reset. Accounts and their files stay. Apps from the Store and system settings you changed go.")
        actionText: root.l10n.i18nc("@action:button", "&Reset")
        actionIcon: "edit-reset"
        cancelText: root.l10n.i18nc("@action:button", "Cancel")
        onConfirmed: root.reset.reset(true)
    }

    Question {
        id: eraseDialog

        title: root.l10n.i18nc("@title:dialog", "Remove everything from this PC?")
        subtitle: root.l10n.i18nc("@info",
            "After the restart, every account on this PC and every file in them is gone for good. Copy anything you want to keep to another drive or online storage first. Windows and other drives aren't touched.")
        actionText: root.l10n.i18nc("@action:button", "Remove &everything")
        actionIcon: "edit-delete"
        cancelText: root.l10n.i18nc("@action:button", "Cancel")
        destructive: true
        onConfirmed: root.reset.reset(false)
    }
}
