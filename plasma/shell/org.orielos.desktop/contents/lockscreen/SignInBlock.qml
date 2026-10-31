/*
    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

// The sign-in part of OrielOS's lock screen, in Sill's style: the account picture, the name and a
// pill-shaped password box with its reveal and submit buttons, centred on the blurred wallpaper.
// It keeps the interface of Plasma's MainBlock.qml (mainPasswordBox, showPassword, passwordResult,
// visibleBoundary), which LockScreenUi.qml and Breeze's virtual keyboard loader use.

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker
import org.kde.coreaddons as KCoreAddons

import org.kde.breeze.components

FocusScope {
    id: block

    readonly property alias mainPasswordBox: passwordBox
    property alias showPassword: passwordBox.showPassword
    property bool lockScreenUiVisible: false
    property ListModel userListModel
    property string notificationMessage
    // After repeated wrong passwords (Lockout.qml): a phrase to type instead, and the seconds until
    // a password is taken again.
    property string challenge: ""
    property int waitSeconds: 0
    // The y position kept visible above the on-screen keyboard.
    readonly property int visibleBoundary: column.y + field.y + field.height + Kirigami.Units.smallSpacing
    default property alias extraContent: extras.data

    readonly property string userName: userListModel && userListModel.count > 0 ? userListModel.get(0).realName : ""
    readonly property string userIcon: userListModel && userListModel.count > 0 ? userListModel.get(0).icon : ""
    // With a PIN, the box takes the PIN and signs in on its last digit (SignInOptions.qml).
    readonly property bool pinMode: signInOptions.pinMode && challenge === ""

    KCoreAddons.KUser {
        id: account
    }

    signal passwordResult(string password)
    signal challengeResult(string text)

    function startLogin() {
        // Moving focus off the field first also works round QTBUG-55460.
        submitButton.forceActiveFocus();
        if (challenge !== "") {
            challengeResult(passwordBox.text);
        } else {
            passwordResult(passwordBox.text);
        }
    }

    function playHighlightAnimation() {
        shake.start();
    }

    ColumnLayout {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(block.height * 0.26)
        width: Math.min(Kirigami.Units.gridUnit * 22, block.width - Kirigami.Units.gridUnit * 2)
        spacing: 0

        // The account picture, with a thin light ring and a faint glow around it.
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7 + 16
            Layout.preferredHeight: Kirigami.Units.gridUnit * 7 + 16
            radius: width / 2
            color: Qt.rgba(156 / 255, 194 / 255, 1, 0.10)
            Accessible.ignored: true

            AccountPicture {
                anchors.fill: parent
                anchors.margins: 8
                source: block.userIcon
                name: block.userName
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 7
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.35)
            }
        }

        PlasmaComponents3.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.gridUnit
            text: block.userName
            textFormat: Text.PlainText
            font.family: "Noto Sans Display"
            font.pixelSize: 30
            font.weight: Font.Bold
            elide: Text.ElideRight
        }

        Rectangle {
            id: field
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.gridUnit * 1.5
            Layout.preferredWidth: Math.min(Kirigami.Units.gridUnit * 18, column.width)
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
            radius: height / 2
            color: Qt.rgba(12 / 255, 21 / 255, 48 / 255, 0.55)
            border.width: 1
            border.color: passwordBox.activeFocus ? Qt.rgba(156 / 255, 194 / 255, 1, 0.8) : Qt.rgba(1, 1, 1, 0.18)

            RejectPasswordAnimation {
                id: shake
                target: field
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.gridUnit
                anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.PasswordField {
                    id: passwordBox
                    Layout.fillWidth: true
                    background: null
                    font.pixelSize: 15
                    text: PasswordSync.password
                    placeholderText: block.challenge !== ""
                        ? i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:placeholder in text field, %1 is a phrase such as A1B2C3", "Type %1", block.challenge)
                        : block.pinMode
                            ? i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:placeholder in text field", "PIN")
                            : i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:placeholder in text field", "Password")
                    validator: block.pinMode ? digitsOnly : null
                    inputMethodHints: block.pinMode ? Qt.ImhDigitsOnly : Qt.ImhNone
                    focus: true
                    enabled: !authenticator.graceLocked && block.waitSeconds === 0
                    // The field stays focused while hidden, to wake the screen on a key press;
                    // a blinking cursor there would keep redrawing it.
                    cursorVisible: visible

                    onAccepted: {
                        if (block.lockScreenUiVisible) {
                            block.startLogin();
                        }
                    }
                    // Signing in on the PIN's last digit, without Enter. Never for a password,
                    // which would count failed attempts and give away its length.
                    onTextChanged: {
                        if (block.pinMode && block.lockScreenUiVisible && text.length === signInOptions.pinLength) {
                            Qt.callLater(block.startLogin);
                        }
                    }

                    RegularExpressionValidator {
                        id: digitsOnly
                        regularExpression: /[0-9]*/
                    }

                    Connections {
                        target: root
                        function onClearPassword() {
                            passwordBox.forceActiveFocus();
                            passwordBox.text = "";
                            passwordBox.text = Qt.binding(() => PasswordSync.password);
                        }
                        function onNotificationRepeated() {
                            block.playHighlightAnimation();
                        }
                    }
                }

                // The phrase is shown as it's typed.
                Binding {
                    target: passwordBox
                    property: "showPassword"
                    value: true
                    when: block.challenge !== ""
                    restoreMode: Binding.RestoreBindingOrValue
                }

                Binding {
                    target: PasswordSync
                    property: "password"
                    value: passwordBox.text
                }

                PlasmaComponents3.ToolButton {
                    id: submitButton
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 2.2
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.2
                    icon.name: LayoutMirroring.enabled ? "go-previous" : "go-next"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button accessible only", "Unlock")
                    onClicked: block.startLogin()
                    Keys.onEnterPressed: clicked()
                    Keys.onReturnPressed: clicked()
                }
            }
        }

        PlasmaComponents3.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.smallSpacing * 2
            Layout.preferredWidth: field.Layout.preferredWidth
            text: block.notificationMessage
            textFormat: Text.PlainText
            color: "#C9D6F5"
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: text.length > 0 ? 1 : 0
            Behavior on opacity {
                OpacityAnimator {
                    duration: Kirigami.Units.shortDuration
                }
            }
        }

        SignInOptions {
            id: signInOptions
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.smallSpacing
            loginName: account.loginName
            domain: "plasma_shell_org.kde.plasma.desktop"
            onPinModeChanged: root.clearPassword()
            onForgotPin: root.notification = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status",
                "Sign in with your password, then set a new PIN in Settings › Accounts › Sign-in options.")
        }

        component FailableLabel: PlasmaComponents3.Label {
            id: failableLabel
            required property int kind
            required property string label

            visible: authenticator.authenticatorTypes & kind
            text: label
            textFormat: Text.PlainText
            color: "#C9D6F5"
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing

            RejectPasswordAnimation {
                id: failShake
                target: failableLabel
                onFinished: failTimer.restart()
            }
            Connections {
                target: authenticator
                function onNoninteractiveError(kind, authenticator) {
                    if (kind & failableLabel.kind) {
                        failableLabel.text = Qt.binding(() => authenticator.errorMessage);
                        failShake.start();
                    }
                }
            }
            Timer {
                id: failTimer
                interval: Kirigami.Units.humanMoment
                onTriggered: failableLabel.text = Qt.binding(() => failableLabel.label)
            }
        }

        FailableLabel {
            kind: ScreenLocker.Authenticator.Fingerprint
            label: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "(or scan your fingerprint on the reader)")
        }
        FailableLabel {
            kind: ScreenLocker.Authenticator.Smartcard
            label: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "(or scan your smartcard)")
        }

        ColumnLayout {
            id: extras
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit
        }
    }
}
