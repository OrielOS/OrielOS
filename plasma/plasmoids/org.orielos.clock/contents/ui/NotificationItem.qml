// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// One notification in the centre, as Sill draws it: a card with the app's icon, its name and how
// long ago, a close button, the title in bold, the text, and its actions as buttons, the first one
// in the highlight colour. Clicking the card does the notification's default action.
Rectangle {
    id: item

    required property int index
    required property var history
    required property date now
    required property string applicationName
    required property string applicationIconName
    required property string summary
    required property string body
    required property date created
    required property bool closable
    required property bool hasDefaultAction
    required property list<string> actionNames
    required property list<string> actionLabels

    function modelIndex() {
        return item.history.index(item.index, 0);
    }

    // "now", "8 min ago", "1 h ago", then the time and, after today, the day.
    readonly property string age: {
        const minutes = Math.floor((item.now.getTime() - item.created.getTime()) / 60000);
        if (minutes < 1) {
            return i18nc("@info:status a notification arrived", "now");
        }
        if (minutes < 60) {
            return i18nc("@info:status %1 is a number of minutes", "%1 min ago", minutes);
        }
        if (minutes < 6 * 60) {
            return i18nc("@info:status %1 is a number of hours", "%1 h ago", Math.floor(minutes / 60));
        }
        if (item.created.toDateString() === item.now.toDateString()) {
            return item.created.toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
        }
        return item.created.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }

    implicitHeight: content.implicitHeight + 28
    radius: 6
    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, hover.hovered ? 0.07 : 0.04)
    border.width: 1
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)

    HoverHandler {
        id: hover
    }

    TapHandler {
        enabled: item.hasDefaultAction
        onTapped: item.history.invokeDefaultAction(item.modelIndex())
    }

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: 14
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Kirigami.Icon {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                source: item.applicationIconName.length > 0 ? item.applicationIconName : "preferences-desktop-notification"
            }

            PC3.Label {
                Layout.fillWidth: true
                text: i18nc("@info %1 is an app, %2 how long ago its notification came", "%1 · %2", item.applicationName, item.age)
                textFormat: Text.PlainText
                font.pixelSize: 12
                opacity: 0.8
                elide: Text.ElideRight
            }

            PC3.ToolButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                visible: item.closable
                icon.name: "window-close"
                icon.width: 12
                icon.height: 12
                display: PC3.AbstractButton.IconOnly
                text: i18nc("@action:button", "Close")
                Accessible.name: text
                onClicked: item.history.close(item.modelIndex())
            }
        }

        PC3.Label {
            Layout.fillWidth: true
            Layout.topMargin: 6
            visible: text.length > 0
            text: item.summary
            textFormat: Text.PlainText
            font.pixelSize: 14
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        PC3.Label {
            Layout.fillWidth: true
            visible: text.length > 0
            text: item.body
            textFormat: Text.StyledText
            font.pixelSize: 13
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            onLinkActivated: link => Qt.openUrlExternally(link)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: item.actionNames.length > 0
            spacing: 8

            Repeater {
                model: Math.min(3, item.actionNames.length)

                delegate: PC3.ToolButton {
                    id: action

                    required property int index

                    Layout.fillWidth: true
                    text: item.actionLabels[index] ?? ""
                    Accessible.name: text
                    onClicked: item.history.invokeAction(item.modelIndex(), item.actionNames[index])

                    background: Rectangle {
                        implicitHeight: 32
                        radius: 4
                        color: action.index === 0
                            ? Qt.lighter(Kirigami.Theme.highlightColor, action.hovered ? 1.12 : 1.0)
                            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, action.hovered ? 0.14 : 0.08)
                        border.width: action.visualFocus ? 2 : 0
                        border.color: Kirigami.Theme.focusColor
                    }
                    contentItem: PC3.Label {
                        text: action.text
                        textFormat: Text.PlainText
                        font.pixelSize: 13
                        font.weight: action.index === 0 ? Font.DemiBold : Font.Normal
                        color: action.index === 0 ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
