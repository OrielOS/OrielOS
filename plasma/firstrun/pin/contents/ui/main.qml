// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The first-run setup's PIN page, right after the account: a PIN of 4 to 12 digits, typed twice,
// to sign in with instead of the password. It can be left empty to set one up later in Settings.
// Plasma Setup creates the account only as it finishes, so the PIN is handed to the PIN service
// when the page is left, for the account's name, and the service gives it to the account once the
// setup is done. Leaving it empty takes back a PIN handed over before.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import org.kde.plasmasetup
import org.kde.plasmasetup.components as PlasmaSetupComponents
import org.orielos.firstrun

PlasmaSetupComponents.SetupModule {
    id: root

    // Plasma Setup's engine translates its own pages; this page's strings are in OrielOS's domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-first-run"
    }

    readonly property bool empty: pinField.text.length === 0 && repeatField.text.length === 0
    readonly property bool pinValid: pinSetup.isValidPin(pinField.text)
    readonly property bool pinsMatch: pinField.text === repeatField.text

    // Shown only when the setup creates the account, as the account page is.
    available: !AccountController.hasExistingUsers
    nextEnabled: empty || (pinValid && pinsMatch)

    PinSetup {
        id: pinSetup
    }

    contentItem: ColumnLayout {
        id: page

        // Whether the page has been shown: it can be hidden before it ever is, with no account name yet.
        property bool shown: false

        onVisibleChanged: {
            if (visible) {
                shown = true;
                pinField.forceActiveFocus();
            } else if (shown) {
                pinSetup.save(AccountController.username, root.empty ? "" : pinField.text);
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignCenter
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            spacing: Kirigami.Units.largeSpacing

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.l10n.i18nc("@info", "A PIN is quicker to type than your password and works only on this computer.")
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.bottomMargin: Kirigami.Units.gridUnit
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                opacity: 0.75
                text: root.l10n.i18nc("@info", "Your password always works too. To skip this, leave both boxes empty; you can set up a PIN later in Settings, under Accounts.")
            }

            QQC2.Label {
                text: root.l10n.i18nc("@label:textbox", "PIN (4 to 12 digits)")
            }

            QQC2.TextField {
                id: pinField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData
                maximumLength: 12
                // Only digits: anything else typed is dropped.
                validator: RegularExpressionValidator {
                    regularExpression: /[0-9]{0,12}/
                }
                Accessible.name: root.l10n.i18nc("@label:textbox", "PIN (4 to 12 digits)")
                Keys.onReturnPressed: repeatField.forceActiveFocus()
                Keys.onEnterPressed: repeatField.forceActiveFocus()
            }

            QQC2.Label {
                text: root.l10n.i18nc("@label:textbox", "Confirm the PIN")
            }

            QQC2.TextField {
                id: repeatField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData
                maximumLength: 12
                validator: RegularExpressionValidator {
                    regularExpression: /[0-9]{0,12}/
                }
                Accessible.name: root.l10n.i18nc("@label:textbox", "Confirm the PIN")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: text.length > 0
                type: pinSetup.error.length > 0 ? Kirigami.MessageType.Warning : Kirigami.MessageType.Information
                text: {
                    if (pinSetup.error.length > 0) {
                        return pinSetup.error;
                    }
                    if (root.empty) {
                        return "";
                    }
                    if (pinField.text.length > 0 && pinField.text.length < 4 && !pinField.activeFocus) {
                        return root.l10n.i18nc("@info", "A PIN has at least 4 digits.");
                    }
                    if (root.pinValid && repeatField.text.length >= pinField.text.length && !root.pinsMatch) {
                        return root.l10n.i18nc("@info", "The PINs don't match.");
                    }
                    return "";
                }
            }
        }
    }
}
