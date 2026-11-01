// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The administrator prompt, laid out as Windows lays out its own: the screen dimmed, and on it the
// question, the app and its publisher (a warning colour when unknown), Show more details, the
// password or PIN, and Yes and No. It covers the screen above everything and holds the keyboard
// while it asks, so nothing else can be clicked or typed into until it's answered.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import org.orielos.polkitagent

QQC2.ApplicationWindow {
    id: root

    required property Agent agent
    property bool showingDetails: false
    // PAM asking again, after a wrong password, puts the cursor back in the box.
    readonly property bool waiting: root.agent.waitingForAnswer

    onWaitingChanged: {
        if (root.waiting) {
            secret.forceActiveFocus();
        }
    }

    function answer() {
        if (root.agent.waitingForAnswer) {
            root.agent.answer(secret.text);
            secret.clear();
        }
    }

    visible: root.agent.asking
    color: Qt.rgba(0, 0, 0, 0.55)
    title: KI18n.i18nc("@title:window", "Administrator permission")

    onVisibleChanged: {
        root.showingDetails = false;
        secret.clear();
        if (visible) {
            secret.forceActiveFocus();
        }
    }


    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: root.agent.refuse()
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Kirigami.Units.gridUnit * 26
        height: content.implicitHeight + Kirigami.Units.gridUnit * 2
        radius: 8
        color: Kirigami.Theme.backgroundColor
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        ColumnLayout {
            id: content

            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.largeSpacing

            QQC2.Label {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                font: Kirigami.Theme.smallFont
                opacity: 0.8
                text: KI18n.i18nc("@title", "Administrator permission")
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 2
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: KI18n.i18nc("@title", "Do you want to allow this app to make changes to your device?")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    implicitWidth: Kirigami.Units.iconSizes.large
                    implicitHeight: Kirigami.Units.iconSizes.large
                    source: root.agent.iconName.length > 0 ? root.agent.iconName : "application-x-executable"
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.weight: Font.DemiBold
                    text: root.agent.name
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: root.agent.verified ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
                text: root.agent.verified
                    ? KI18n.i18nc("@info %1 is who made the app", "Verified publisher: %1", root.agent.publisher)
                    : KI18n.i18nc("@info", "Publisher: Unknown")
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: root.agent.program.length > 0
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: root.agent.verified
                    ? KI18n.i18nc("@info Where the program is", "File origin: part of OrielOS")
                    : KI18n.i18nc("@info Where the program is", "File origin: a drive on this computer")
            }

            Kirigami.LinkButton {
                text: root.showingDetails ? KI18n.i18nc("@action:button", "Show fewer details") : KI18n.i18nc("@action:button", "Show more details")
                onClicked: root.showingDetails = !root.showingDetails
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: root.showingDetails
                wrapMode: Text.WrapAnywhere
                textFormat: Text.PlainText
                font: Kirigami.Theme.smallFont
                text: [
                    root.agent.program.length > 0 ? KI18n.i18nc("@info", "Program location: %1", root.agent.program) : "",
                    root.agent.commandLine.length > 0 ? KI18n.i18nc("@info", "Command: %1", root.agent.commandLine) : "",
                    root.agent.message,
                    KI18n.i18nc("@info", "Action: %1", root.agent.actionId),
                ].filter(line => line.length > 0).join("\n")
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: KI18n.i18nc("@info %1 is an account name", "To continue, sign in as %1.", root.agent.account)
            }

            Kirigami.PasswordField {
                id: secret

                Layout.fillWidth: true
                enabled: root.agent.waitingForAnswer
                echoMode: root.agent.echo ? TextInput.Normal : TextInput.Password
                // PAM's own words: the password, or OrielOS's PIN prompt.
                placeholderText: root.agent.prompt.replace(/:\s*$/, "")
                Accessible.name: placeholderText
                onAccepted: root.answer()
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: text.length > 0
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: root.agent.error.length > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                text: root.agent.error.length > 0 ? root.agent.error : root.agent.info
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing

                QQC2.Button {
                    Layout.fillWidth: true
                    text: KI18n.i18nc("@action:button Allow the change", "Yes")
                    highlighted: true
                    enabled: root.agent.waitingForAnswer
                    onClicked: root.answer()
                }

                QQC2.Button {
                    Layout.fillWidth: true
                    text: KI18n.i18nc("@action:button Don't allow the change", "No")
                    onClicked: root.agent.refuse()
                }
            }
        }
    }
}
