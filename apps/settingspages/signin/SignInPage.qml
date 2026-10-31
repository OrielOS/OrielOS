// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// Sign-in options, as in Windows: a PIN, fingerprints, face sign-in (not yet), dynamic lock, and the
// sign-in and lock screens' settings. The PIN is kept by OrielOS's PIN service, which needs the
// password or the current PIN to set or remove it.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property SignInOptions options: SignInOptions {}
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

    component Explanation: QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }

    component Note: QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        font: Kirigami.Theme.smallFont
        opacity: 0.8
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.options.error.length > 0
            type: Kirigami.MessageType.Error
            text: root.options.error
        }

        // PIN
        Kirigami.Heading {
            level: 3
            text: root.l10n.i18nc("@title:group", "PIN")
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: !root.options.pinServiceAvailable
            type: Kirigami.MessageType.Warning
            text: root.l10n.i18nc("@info", "The PIN service isn't running, so a PIN can't be set up.")
        }
        Explanation {
            text: root.options.hasPin
                ? root.l10n.i18ncp("@info", "You sign in with a %1-digit PIN.", "You sign in with a %1-digit PIN.", root.options.pinLength)
                : root.l10n.i18nc("@info", "Sign in faster with a PIN instead of your password.")
        }
        RowLayout {
            enabled: root.options.pinServiceAvailable && !root.options.busy
            QQC2.Button {
                text: root.options.hasPin ? root.l10n.i18nc("@action:button", "Change PIN") : root.l10n.i18nc("@action:button", "Set up")
                onClicked: pinDialog.openFor(true)
            }
            QQC2.Button {
                visible: root.options.hasPin
                text: root.l10n.i18nc("@action:button", "Remove")
                onClicked: pinDialog.openFor(false)
            }
        }
        Note {
            text: root.l10n.i18nc("@info", "Your PIN works only on this computer. After five wrong PINs, OrielOS waits before you can try again; your password always works.")
        }

        // Fingerprint
        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.largeSpacing
            level: 3
            text: root.l10n.i18nc("@title:group", "Fingerprint")
        }
        Explanation {
            text: root.options.fingerprintReaderPresent
                ? root.l10n.i18nc("@info", "Unlock and confirm changes with your finger.")
                : root.l10n.i18nc("@info", "No fingerprint reader was found.")
        }
        QQC2.Button {
            visible: root.options.fingerprintReaderPresent
            text: root.l10n.i18nc("@action:button", "Set up")
            onClicked: root.options.openFingerprintSetup()
        }

        // Facial recognition
        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.largeSpacing
            level: 3
            text: root.l10n.i18nc("@title:group", "Facial recognition")
        }
        Explanation {
            text: root.l10n.i18nc("@info", "Face sign-in needs an infrared camera made for Windows Hello. OrielOS doesn't support it yet.")
        }

        // Dynamic lock
        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.largeSpacing
            level: 3
            text: root.l10n.i18nc("@title:group", "Dynamic lock")
        }
        QQC2.CheckBox {
            id: dynamicLockBox
            enabled: root.options.pairedDevices.length > 0
            text: root.l10n.i18nc("@option:check", "Lock your computer when you're away")
            checked: root.options.dynamicLockEnabled
            onToggled: {
                root.options.setDynamicLock(checked, deviceBox.currentValue ?? "");
                checked = Qt.binding(() => root.options.dynamicLockEnabled);
            }
        }
        QQC2.ComboBox {
            id: deviceBox
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            visible: root.options.pairedDevices.length > 0
            enabled: dynamicLockBox.checked
            model: root.options.pairedDevices
            textRole: "name"
            valueRole: "address"
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(root.options.dynamicLockDevice))
            onActivated: root.options.setDynamicLock(true, currentValue)
        }
        Explanation {
            text: root.options.pairedDevices.length > 0
                ? root.l10n.i18nc("@info", "OrielOS locks the computer about a minute after your phone goes out of Bluetooth range. Pair your phone in Bluetooth & devices first.")
                : root.l10n.i18nc("@info", "No paired Bluetooth devices. Pair your phone in Bluetooth & devices first.")
        }

        // Additional settings
        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.largeSpacing
            level: 3
            text: root.l10n.i18nc("@title:group", "Additional settings")
        }
        QQC2.Switch {
            text: root.l10n.i18nc("@option:check", "Ask for sign-in after the computer wakes from sleep")
            checked: root.options.lockOnResume
            onToggled: {
                root.options.lockOnResume = checked;
                checked = Qt.binding(() => root.options.lockOnResume);
            }
        }
        QQC2.Switch {
            enabled: !root.options.busy
            text: root.l10n.i18nc("@option:check", "Ask for Ctrl+Alt+Delete before signing in")
            checked: root.options.requireCtrlAltDel
            onToggled: {
                root.options.requireCtrlAltDel = checked;
                checked = Qt.binding(() => root.options.requireCtrlAltDel);
            }
        }
        Note {
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            text: root.l10n.i18nc("@info", "Needs an administrator. No app can fake these keys, so you know you're typing into the real sign-in screen.")
        }
        QQC2.Switch {
            enabled: !root.options.busy
            text: root.l10n.i18nc("@option:check", "Play a sound when the sign-in screen appears after starting")
            checked: root.options.startupSound
            onToggled: {
                root.options.startupSound = checked;
                checked = Qt.binding(() => root.options.startupSound);
            }
        }
        Note {
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            text: root.l10n.i18nc("@info", "Needs an administrator.")
        }
    }

    // Setting, changing or removing the PIN: the password or current PIN, and the new PIN twice.
    Kirigami.PromptDialog {
        id: pinDialog

        property bool setting: true

        function openFor(set: bool) {
            setting = set;
            credentialField.text = "";
            newPinField.text = "";
            repeatField.text = "";
            open();
            credentialField.forceActiveFocus();
        }

        readonly property bool pinsMatch: newPinField.text === repeatField.text
        readonly property bool acceptable: credentialField.text.length > 0
            && (!setting || (newPinField.text.length >= 4 && pinsMatch))

        title: !setting ? root.l10n.i18nc("@title:window", "Remove your PIN")
            : root.options.hasPin ? root.l10n.i18nc("@title:window", "Change your PIN")
            : root.l10n.i18nc("@title:window", "Set up a PIN")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel

        Component.onCompleted: standardButton(QQC2.Dialog.Ok).enabled = Qt.binding(() => pinDialog.acceptable)

        onAccepted: {
            if (setting) {
                root.options.setPin(newPinField.text, credentialField.text);
            } else {
                root.options.removePin(credentialField.text);
            }
        }

        RegularExpressionValidator {
            id: pinDigits
            regularExpression: /[0-9]{0,12}/
        }

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: root.options.hasPin
                    ? root.l10n.i18nc("@label:textbox", "Your password or current PIN")
                    : root.l10n.i18nc("@label:textbox", "Your password")
            }
            Kirigami.PasswordField {
                id: credentialField
                Layout.fillWidth: true
            }
            QQC2.Label {
                visible: pinDialog.setting
                text: root.l10n.i18nc("@label:textbox", "New PIN (4 to 12 digits)")
            }
            Kirigami.PasswordField {
                id: newPinField
                Layout.fillWidth: true
                visible: pinDialog.setting
                validator: pinDigits
                inputMethodHints: Qt.ImhDigitsOnly
            }
            QQC2.Label {
                visible: pinDialog.setting
                text: root.l10n.i18nc("@label:textbox", "Confirm the new PIN")
            }
            Kirigami.PasswordField {
                id: repeatField
                Layout.fillWidth: true
                visible: pinDialog.setting
                validator: pinDigits
                inputMethodHints: Qt.ImhDigitsOnly
            }
            QQC2.Label {
                visible: pinDialog.setting && repeatField.text.length > 0 && !pinDialog.pinsMatch
                text: root.l10n.i18nc("@info", "The PINs don't match.")
                color: Kirigami.Theme.negativeTextColor
            }
        }
    }
}
