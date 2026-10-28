// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// One of Quick Settings' sub-pages (Wi-Fi, Bluetooth, sound output), which takes the settings
// card's place: a back arrow and the page's name, with a switch on the right when the page has one,
// then its list, then a footer band with a link to the matching page of Settings.
ColumnLayout {
    id: page

    required property var quickSettings
    property int inset: 20
    property string title
    // Whether the header shows a switch, and its state; `toggled` asks to flip it.
    property bool hasSwitch: false
    property bool switchChecked: false
    property bool switchEnabled: true
    // The link in the footer and the Settings page it opens.
    property string moreText
    property string morePage
    // Extra buttons on the footer's left, before the link.
    property alias footerItems: footerRow.data
    // The page's list, which fills the space between the header and the footer.
    default property alias content: body.data

    signal back()
    signal toggled()

    spacing: 0

    Keys.onEscapePressed: page.back()

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: page.inset - 6
        Layout.rightMargin: page.inset
        Layout.topMargin: page.inset - 6
        Layout.bottomMargin: 8
        spacing: 6

        MediaButton {
            iconName: "go-previous"
            accessibleName: i18nc("@action:button Back to Quick Settings", "Back")
            onClicked: page.back()
        }

        PC3.Label {
            Layout.fillWidth: true
            text: page.title
            textFormat: Text.PlainText
            font.pixelSize: 14
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            Accessible.role: Accessible.Heading
        }

        PC3.Switch {
            visible: page.hasSwitch
            checked: page.switchChecked
            enabled: page.switchEnabled
            Accessible.name: page.title
            onToggled: page.toggled()
        }
    }

    Item {
        id: body

        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
    }

    PanelFooter {
        Layout.fillWidth: true
        quickSettings: page.quickSettings
        inset: page.inset
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                id: footerRow
                spacing: Kirigami.Units.smallSpacing
            }

            Item {
                Layout.fillWidth: true
            }

            PC3.ToolButton {
                text: page.moreText
                font.pixelSize: 12
                onClicked: page.quickSettings.openSettings(page.morePage)
            }
        }
    }
}
