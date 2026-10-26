// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The Update settings page. Every button and option carries a mnemonic (Alt and the underlined
// letter), each letter used once on the page and its dialogs, and not C, which kcmshell6's Close
// button has. The rows have no form labels, which would take letters of their own; the section
// headings name them.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property UpdateSettings settings: UpdateSettings {}
    // System Settings' engine doesn't set up the KI18n singleton, and the page's strings are in the
    // module's own translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "kcm_orielos_update"
    }

    // Clicking a radio button sets it checked by itself; the channel shown must stay the one the
    // settings report, which changes only once orielos-update has switched.
    function showChannel(): void {
        stableButton.checked = Qt.binding(() => root.settings.channel === 0);
        testingButton.checked = Qt.binding(() => root.settings.channel === 1);
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

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                Layout.alignment: Qt.AlignTop
                source: "system-software-update"
                Accessible.ignored: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 2
                    text: root.settings.headline
                    wrapMode: Text.Wrap
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.settings.detail
                    wrapMode: Text.Wrap
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.settings.lastChecked
                    wrapMode: Text.Wrap
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    visible: root.settings.runningVersion.length > 0
                    text: root.l10n.i18nc("@info %1 is a version such as 44.20261026", "OrielOS %1", root.settings.runningVersion)
                    wrapMode: Text.Wrap
                }
            }

            QQC2.BusyIndicator {
                Layout.alignment: Qt.AlignTop
                visible: root.settings.checking
                running: root.settings.checking
            }

            QQC2.Button {
                Layout.alignment: Qt.AlignTop
                text: root.l10n.i18nc("@action:button", "Check for &updates")
                icon.name: "view-refresh"
                enabled: !root.settings.checking && !root.settings.busy
                onClicked: root.settings.checkForUpdates()
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.settings.updateWaiting
            type: Kirigami.MessageType.Positive
            text: root.l10n.i18nc("@info", "OrielOS %1 is ready. Restart to finish updating. Your files and apps stay as they are.", root.settings.stagedVersion)
            actions: [
                Kirigami.Action {
                    text: root.l10n.i18nc("@action:button", "Restart &now")
                    icon.name: "system-reboot"
                    onTriggered: root.settings.restart()
                }
            ]
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.settings.goingBack
            type: Kirigami.MessageType.Information
            text: root.l10n.i18nc("@info", "OrielOS %1 starts after a restart. Your files and apps stay as they are.", root.settings.previousVersion)
            actions: [
                Kirigami.Action {
                    text: root.l10n.i18nc("@action:button", "Restart &now")
                    icon.name: "system-reboot"
                    onTriggered: root.settings.restart()
                }
            ]
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.settings.error.length > 0
            type: Kirigami.MessageType.Error
            text: root.settings.error
            showCloseButton: true
            onVisibleChanged: {
                // The close button hides the message by setting visible, which ends the binding:
                // forget the error and bind again, so the next one shows.
                if (!visible) {
                    root.settings.clearError();
                    visible = Qt.binding(() => root.settings.error.length > 0);
                }
            }
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: root.l10n.i18nc("@title:group", "Pause updates")
            }

            // A button's mnemonic is fixed when the button is made: showing it later, or changing its
            // text, leaves Alt and its letter doing nothing. So the loader makes a new Pause or Resume
            // button each time the pause starts or ends.
            RowLayout {
                spacing: Kirigami.Units.smallSpacing

                QQC2.ComboBox {
                    id: pauseLength

                    visible: !root.settings.paused
                    model: root.settings.pauseChoices
                    enabled: !root.settings.busy
                    Accessible.name: root.l10n.i18nc("@label:listbox", "How long to pause updates for")
                }

                QQC2.Label {
                    visible: root.settings.paused
                    text: root.l10n.i18nc("@info %1 is a date", "Updates are paused until %1.", root.settings.pausedUntil)
                    wrapMode: Text.Wrap
                }

                Loader {
                    sourceComponent: root.settings.paused ? resumeButton : pauseButton
                }

                Component {
                    id: pauseButton

                    QQC2.Button {
                        text: root.l10n.i18nc("@action:button", "&Pause updates")
                        icon.name: "media-playback-pause"
                        enabled: !root.settings.busy
                        onClicked: root.settings.pause(root.settings.minPauseWeeks + pauseLength.currentIndex)
                    }
                }

                Component {
                    id: resumeButton

                    QQC2.Button {
                        text: root.l10n.i18nc("@action:button", "&Resume updates")
                        icon.name: "media-playback-start"
                        enabled: !root.settings.busy
                        onClicked: root.settings.resume()
                    }
                }
            }

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: root.l10n.i18nc("@title:group", "Update channel")
            }

            QQC2.ButtonGroup {
                id: channelGroup
            }

            QQC2.RadioButton {
                id: stableButton

                QQC2.ButtonGroup.group: channelGroup
                text: root.l10n.i18nc("@option:radio", "&Stable (recommended)")
                checked: root.settings.channel === 0
                enabled: !root.settings.busy
                onClicked: {
                    root.settings.setChannel(0);
                    root.showChannel();
                }
            }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                text: root.l10n.i18nc("@info", "Builds that people have already used on the testing channel.")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
            }

            QQC2.RadioButton {
                id: testingButton

                QQC2.ButtonGroup.group: channelGroup
                text: root.l10n.i18nc("@option:radio", "&Testing: new builds sooner, less tested")
                checked: root.settings.channel === 1
                enabled: !root.settings.busy
                onClicked: {
                    root.settings.setChannel(1);
                    root.showChannel();
                }
            }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                text: root.l10n.i18nc("@info", "Every new build as soon as it passes the automatic checks. Something may break now and then; you can always go back.")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
            }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                text: root.l10n.i18nc("@info", "Changing the channel needs an administrator's password.")
                wrapMode: Text.Wrap
            }

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: root.l10n.i18nc("@title:group", "Previous version")
                visible: root.settings.hasPrevious
            }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                visible: root.settings.hasPrevious
                wrapMode: Text.Wrap
                text: {
                    // A version gone back from, or one that didn't start, isn't offered again.
                    if (!root.settings.canGoBack && !root.settings.goingBack) {
                        return root.l10n.i18nc("@info", "OrielOS %1 is still on this computer, but isn't offered again.", root.settings.previousVersion);
                    }
                    if (root.settings.previousAvailableUntil.length > 0) {
                        return root.l10n.i18nc("@info %2 is a date", "OrielOS %1 is kept on this computer until %2.", root.settings.previousVersion, root.settings.previousAvailableUntil);
                    }
                    return root.l10n.i18nc("@info", "OrielOS %1 is kept on this computer.", root.settings.previousVersion);
                }
            }

            QQC2.Button {
                visible: root.settings.canGoBack
                enabled: !root.settings.busy
                text: root.l10n.i18nc("@action:button", "&Go back to the previous version…")
                icon.name: "edit-undo"
                onClicked: goBackDialog.open()
            }

            QQC2.Button {
                visible: root.settings.hasPrevious
                enabled: root.settings.canRemovePrevious && !root.settings.busy
                text: root.l10n.i18nc("@action:button", "Re&move the previous version…")
                icon.name: "edit-delete"
                onClicked: removeDialog.open()
            }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                visible: root.settings.hasPrevious
                text: root.l10n.i18nc("@info", "Going back and removing the previous version need an administrator's password.")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
            }
        }
    }

    ConfirmationDialog {
        id: goBackDialog

        title: root.l10n.i18nc("@title:dialog", "Go back to the previous version")
        subtitle: root.l10n.i18nc("@info",
            "OrielOS %1 starts after you restart. OrielOS %2, the version running now, won't be offered again; a newer version will be. Your files and apps stay as they are.",
            root.settings.previousVersion, root.settings.runningVersion)
        actionText: root.l10n.i18nc("@action:button", "Go &back")
        actionIcon: "edit-undo"
        cancelText: root.l10n.i18nc("@action:button", "Cancel")
        onConfirmed: root.settings.goBack()
    }

    ConfirmationDialog {
        id: removeDialog

        title: root.l10n.i18nc("@title:dialog", "Remove the previous version")
        subtitle: root.l10n.i18nc("@info", "OrielOS %1 is removed now, and you won't be able to go back to it. Your files and apps stay as they are.", root.settings.previousVersion)
        actionText: root.l10n.i18nc("@action:button", "R&emove")
        actionIcon: "edit-delete"
        cancelText: root.l10n.i18nc("@action:button", "Cancel")
        onConfirmed: root.settings.removePrevious()
    }
}
