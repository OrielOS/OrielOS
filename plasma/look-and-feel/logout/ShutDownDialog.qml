// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// Windows' small Shut down dialog, which Alt+F4 on the desktop opens: what the computer should do,
// chosen from a list (Switch user, Sign out, Sleep, Shut down, Restart), with Shut down chosen, and
// OK and Cancel. Enter is OK and Escape is Cancel.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Rectangle {
    id: dialog

    // The log-out screen whose signals do the work.
    required property var logout
    property bool canSwitchUser: false

    signal switchUserRequested()

    readonly property var choices: [
        { id: "switch-user", text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@item:inlistbox", "Switch user"), shown: dialog.canSwitchUser },
        { id: "sign-out", text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@item:inlistbox", "Sign out"), shown: canLogout },
        { id: "sleep", text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@item:inlistbox", "Sleep"), shown: spdMethods.SuspendState },
        { id: "shut-down", text: softwareUpdatePending ? i18ndc("plasma_lookandfeel_org.orielos.desktop", "@item:inlistbox", "Update and shut down")
                                                       : i18ndc("plasma_lookandfeel_org.orielos.desktop", "@item:inlistbox", "Shut down"), shown: maysd },
        { id: "restart", text: softwareUpdatePending ? i18ndc("plasma_lookandfeel_org.orielos.desktop", "@item:inlistbox", "Update and restart")
                                                     : i18ndc("plasma_lookandfeel_org.orielos.desktop", "@item:inlistbox", "Restart"), shown: maysd },
    ].filter(choice => choice.shown)

    function accept() {
        switch (dialog.choices[list.currentIndex]?.id) {
        case "switch-user":
            dialog.switchUserRequested();
            break;
        case "sign-out":
            dialog.logout.logoutRequested();
            break;
        case "sleep":
            dialog.logout.sleepRequested();
            break;
        case "shut-down":
            softwareUpdatePending ? dialog.logout.haltUpdateRequested() : dialog.logout.haltRequested();
            break;
        case "restart":
            softwareUpdatePending ? dialog.logout.rebootUpdateRequested() : dialog.logout.rebootRequested();
            break;
        }
    }

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    implicitWidth: 440
    implicitHeight: content.implicitHeight + 40
    radius: 8
    color: Kirigami.Theme.backgroundColor
    border.width: 1
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.13)

    Keys.onReturnPressed: dialog.accept()
    Keys.onEnterPressed: dialog.accept()
    Keys.onEscapePressed: dialog.logout.cancelRequested()

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        RowLayout {
            spacing: 12

            Kirigami.Icon {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                source: "orielos-start"
            }

            PC3.Label {
                Layout.fillWidth: true
                text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@title", "Shut down OrielOS")
                textFormat: Text.PlainText
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }
        }

        PC3.Label {
            text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@label:listbox", "What do you want the computer to do?")
            textFormat: Text.PlainText
        }

        QQC2.ComboBox {
            id: list

            Layout.fillWidth: true
            focus: true
            model: dialog.choices
            textRole: "text"
            currentIndex: Math.max(0, dialog.choices.findIndex(choice => choice.id === "shut-down"))
            Accessible.name: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@label:listbox", "What do you want the computer to do?")
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: 6
            spacing: 8

            QQC2.Button {
                text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:button", "OK")
                highlighted: true
                onClicked: dialog.accept()
            }

            QQC2.Button {
                text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:button", "Cancel")
                onClicked: dialog.logout.cancelRequested()
            }
        }
    }
}
