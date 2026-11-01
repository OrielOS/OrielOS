// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// Plasma's log-out screen, as OrielOS's Ctrl+Alt+Del screen, laid out the way Windows does it: the
// desktop gives way to a plain dark page with Lock, Switch user, Sign out, Change a password and
// System Monitor in the middle, Cancel below them, and the power button at the bottom right (Sleep,
// Shut down, Restart). Plasma shows it for Ctrl+Alt+Del and whenever something asks for it; Start's
// Shut down and Restart don't, as /etc/xdg/ksmserverrc turns the confirmation off. Asked to shut down
// (as Alt+F4 on the desktop asks), it shows Windows' small Shut down dialog instead.
//
// Plasma's log-out greeter loads this file from the look-and-feel package and gives it these context
// properties: canLogout, maysd (shutting down is allowed), spdMethods (the sleep methods),
// softwareUpdatePending, sdtype and screenGeometry. It answers the signals below.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.private.sessions as Sessions
import org.kde.plasma.workspace.dbus as DBus

Item {
    id: root

    signal logoutRequested()
    signal haltRequested()
    signal haltUpdateRequested()
    signal suspendRequested(int spdMethod)
    signal rebootRequested()
    signal rebootRequested2(int opt)
    signal rebootUpdateRequested()
    signal cancelRequested()
    signal lockScreenRequested()
    signal cancelSoftwareUpdateRequested()

    function sleepRequested() {
        root.suspendRequested(2);
    }

    // Opens an OrielOS Settings page or an app, then leaves this screen.
    function openThen(url: string) {
        Qt.openUrlExternally(url);
        root.cancelRequested();
    }

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary
    height: screenGeometry.height
    width: screenGeometry.width

    Sessions.SessionManagement {
        id: session
    }

    Keys.onEscapePressed: root.cancelRequested()

    // Asked to shut down (Alt+F4 on the desktop): Windows' small Shut down dialog, over the desktop.
    // 2 is KWorkSpace's ShutdownTypeHalt, which the greeter doesn't name to QML outside its own imports.
    readonly property bool askingToShutDown: sdtype === 2

    ShutDownDialog {
        anchors.centerIn: parent
        visible: root.askingToShutDown
        focus: root.askingToShutDown
        logout: root
        canSwitchUser: session.canSwitchUser
        onSwitchUserRequested: {
            session.switchUser();
            root.cancelRequested();
        }
    }

    // Otherwise, the Ctrl+Alt+Del screen.
    Item {
        anchors.fill: parent
        visible: !root.askingToShutDown

        Rectangle {
            anchors.fill: parent
            // OrielOS's Night, solid, as Windows hides the desktop.
            color: "#0b1230"
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: [
                    { text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:button", "Lock"), act: () => root.lockScreenRequested(), shown: true },
                    { text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:button", "Switch user"), act: () => { session.switchUser(); root.cancelRequested(); }, shown: session.canSwitchUser },
                    { text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:button", "Sign out"), act: () => root.logoutRequested(), shown: canLogout },
                    { text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:button", "Change a password"), act: () => root.openThen("orielos-settings:your-info"), shown: true },
                    { text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:button", "System Monitor"), act: () => { systemMonitor.call(); root.cancelRequested(); }, shown: true },
                ]

                delegate: QQC2.AbstractButton {
                    id: link

                    required property var modelData
                    required property int index

                    Layout.preferredWidth: 280
                    Layout.preferredHeight: 40
                    visible: link.modelData.shown
                    focus: link.index === 0
                    text: link.modelData.text
                    Accessible.name: text
                    onClicked: link.modelData.act()
                    Keys.onReturnPressed: clicked()
                    Keys.onEnterPressed: clicked()
                    KeyNavigation.down: null

                    background: Rectangle {
                        radius: 4
                        color: Kirigami.Theme.textColor
                        opacity: link.pressed ? 0.14 : (link.hovered ? 0.08 : 0)
                        border.width: link.visualFocus ? 2 : 0
                        border.color: Kirigami.Theme.textColor
                    }

                    contentItem: PC3.Label {
                        text: link.text
                        textFormat: Text.PlainText
                        font.pixelSize: 20
                        leftPadding: 12
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        QQC2.Button {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(parent.height * 0.14)
            text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:button", "Cancel")
            onClicked: root.cancelRequested()
        }

        // The power button, at the bottom right, with Sleep, Shut down and Restart.
        PC3.ToolButton {
            id: powerButton

            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 32
            icon.name: "system-shutdown"
            icon.width: 24
            icon.height: 24
            display: PC3.AbstractButton.IconOnly
            visible: maysd || spdMethods.SuspendState
            text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:button", "Power")
            Accessible.name: text
            onClicked: powerMenu.popup(powerButton, 0, -powerMenu.implicitHeight)

            PC3.Menu {
                id: powerMenu

                PC3.MenuItem {
                    visible: spdMethods.SuspendState
                    text: i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:inmenu", "Sleep")
                    onClicked: root.sleepRequested()
                }
                PC3.MenuItem {
                    visible: maysd
                    text: softwareUpdatePending ? i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:inmenu", "Update and shut down")
                                                : i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:inmenu", "Shut down")
                    onClicked: softwareUpdatePending ? root.haltUpdateRequested() : root.haltRequested()
                }
                PC3.MenuItem {
                    visible: maysd
                    text: softwareUpdatePending ? i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:inmenu", "Update and restart")
                                                : i18ndc("plasma_lookandfeel_org.orielos.desktop", "@action:inmenu", "Restart")
                    onClicked: softwareUpdatePending ? root.rebootUpdateRequested() : root.rebootRequested()
                }
            }
        }
    }

    // System Monitor, which OrielOS starts with Ctrl+Shift+Esc as well.
    QtObject {
        id: systemMonitor

        function call() {
            DBus.SessionBus.asyncCall({
                service: "org.kde.kglobalaccel",
                path: "/component/org_kde_plasma_systemmonitor_desktop",
                iface: "org.kde.kglobalaccel.Component",
                member: "invokeShortcut",
                arguments: ["_launch"],
            });
        }
    }
}
