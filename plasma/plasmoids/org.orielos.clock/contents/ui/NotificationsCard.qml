// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.qmlmodels
import org.kde.kirigami as Kirigami
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.components as PC3

// The notifications card: its heading with Do not disturb and Clear all, then the notifications,
// newest first, or a line saying there are none. An app with more than one notification gets a row
// with its name and a button that clears them all.
Card {
    id: card

    required property var clock

    readonly property var history: card.clock.history
    // A few notifications fit; more scroll.
    readonly property int listHeight: Math.min(list.contentHeight, 420)

    implicitHeight: content.implicitHeight + 32

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: 16
        anchors.leftMargin: 20
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            PC3.Label {
                Layout.fillWidth: true
                text: i18nc("@title", "Notifications")
                textFormat: Text.PlainText
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            PC3.ToolButton {
                icon.name: card.clock.doNotDisturb ? "notifications-disabled" : "notifications"
                display: PC3.AbstractButton.IconOnly
                checkable: true
                checked: card.clock.doNotDisturb
                text: i18nc("@action:button", "Do not disturb")
                Accessible.name: text
                PC3.ToolTip.text: text
                PC3.ToolTip.visible: hovered
                onClicked: card.clock.setDoNotDisturb(card.clock.doNotDisturb ? 0 : 365 * 24 * 60)
            }

            PC3.ToolButton {
                id: clearAll

                implicitHeight: 28
                visible: list.count > 0
                text: i18nc("@action:button Remove every notification", "Clear all")
                Accessible.name: text
                onClicked: card.history.clear(NotificationManager.Notifications.ClearExpired)

                background: Rectangle {
                    implicitHeight: 28
                    radius: height / 2
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, clearAll.hovered ? 0.14 : 0.08)
                    border.width: clearAll.visualFocus ? 2 : 0
                    border.color: Kirigami.Theme.focusColor
                }
                contentItem: PC3.Label {
                    text: clearAll.text
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                leftPadding: 12
                rightPadding: 12
            }
        }

        ListView {
            id: list

            Layout.fillWidth: true
            Layout.preferredHeight: card.listHeight
            visible: count > 0
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: card.history
            reuseItems: false

            delegate: DelegateChooser {
                role: "isGroup"

                DelegateChoice {
                    roleValue: true

                    delegate: RowLayout {
                        id: group

                        required property int index
                        required property string applicationName
                        required property string applicationIconName

                        width: list.width
                        spacing: 8

                        Kirigami.Icon {
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            source: group.applicationIconName || "preferences-desktop-notification-bell"
                        }
                        PC3.Label {
                            Layout.fillWidth: true
                            text: group.applicationName
                            textFormat: Text.PlainText
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        PC3.ToolButton {
                            icon.name: "window-close"
                            display: PC3.AbstractButton.IconOnly
                            text: i18nc("@action:button %1 is an app's name", "Clear %1's notifications", group.applicationName)
                            Accessible.name: text
                            PC3.ToolTip.text: text
                            PC3.ToolTip.visible: hovered
                            onClicked: card.history.close(card.history.index(group.index, 0))
                        }
                    }
                }

                DelegateChoice {
                    delegate: NotificationItem {
                        width: list.width
                        history: card.history
                        now: card.clock.now
                    }
                }
            }
        }

        PC3.Label {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.bottomMargin: 16
            visible: list.count === 0
            text: card.clock.doNotDisturb ? i18nc("@info:status", "Do not disturb is on") : i18nc("@info:status", "No new notifications")
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            opacity: 0.7
        }
    }
}
