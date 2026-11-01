// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The first-run setup's bottom-left corner, as Windows' setup has it on every page: Accessibility
// (screen reader, magnifier, on-screen keyboard, high contrast), the volume and the keyboard
// layout, so someone can turn the sound up, have the screen read or switch layout before typing.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.orielos.setupcorner

Window {
    id: window

    readonly property SetupCorner corner: SetupCorner {}

    width: row.implicitWidth + Kirigami.Units.largeSpacing * 2
    height: row.implicitHeight + Kirigami.Units.largeSpacing * 2
    color: "transparent"
    // main.cpp shows it once it's an overlay in the corner.
    visible: false
    title: KI18n.i18nc("@title:window", "Accessibility, volume and keyboard")

    component CornerButton: QQC2.ToolButton {
        // Hidden while the button's menu or pop-up is open.
        property bool open: false

        display: QQC2.AbstractButton.IconOnly
        icon.width: Kirigami.Units.iconSizes.smallMedium
        icon.height: Kirigami.Units.iconSizes.smallMedium
        QQC2.ToolTip.text: text
        QQC2.ToolTip.visible: hovered && !open
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        Accessible.name: text
    }

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        CornerButton {
            id: accessibilityButton

            text: KI18n.i18nc("@action:button", "Accessibility")
            icon.name: "preferences-desktop-accessibility"
            open: accessibilityMenu.visible
            onClicked: accessibilityMenu.popup(accessibilityButton, 0, -accessibilityMenu.implicitHeight)

            // Menus and pop-ups open as windows of their own: the corner's window is only as big as
            // its buttons.
            QQC2.Menu {
                id: accessibilityMenu

                popupType: QQC2.Popup.Window

                QQC2.MenuItem {
                    text: KI18n.i18nc("@action:inmenu", "Screen reader")
                    icon.name: "preferences-desktop-text-to-speech"
                    onTriggered: window.corner.toggleScreenReader()
                }
                QQC2.MenuItem {
                    text: KI18n.i18nc("@action:inmenu", "Magnifier")
                    icon.name: "zoom-in"
                    checkable: true
                    checked: window.corner.magnified
                    onTriggered: window.corner.toggleMagnifier()
                }
                QQC2.MenuItem {
                    text: KI18n.i18nc("@action:inmenu", "On-screen keyboard")
                    icon.name: "input-keyboard-virtual"
                    checkable: true
                    checked: window.corner.keyboardShown
                    onTriggered: window.corner.toggleKeyboard()
                }
                QQC2.MenuItem {
                    text: KI18n.i18nc("@action:inmenu", "High contrast")
                    icon.name: "preferences-desktop-color"
                    onTriggered: window.corner.toggleContrast()
                }
            }
        }

        CornerButton {
            id: volumeButton

            text: window.corner.muted ? KI18n.i18nc("@action:button", "Volume: muted") : KI18n.i18nc("@action:button %1 is a percentage", "Volume: %1%", window.corner.volume)
            icon.name: window.corner.muted || window.corner.volume === 0 ? "audio-volume-muted"
                : (window.corner.volume < 34 ? "audio-volume-low" : (window.corner.volume < 67 ? "audio-volume-medium" : "audio-volume-high"))
            open: volumePopup.visible
            onClicked: volumePopup.open()

            QQC2.Popup {
                id: volumePopup

                popupType: QQC2.Popup.Window

                y: -height - Kirigami.Units.smallSpacing
                padding: Kirigami.Units.largeSpacing

                RowLayout {
                    QQC2.ToolButton {
                        icon.name: window.corner.muted ? "audio-volume-muted" : "audio-volume-high"
                        display: QQC2.AbstractButton.IconOnly
                        text: window.corner.muted ? KI18n.i18nc("@action:button", "Unmute") : KI18n.i18nc("@action:button", "Mute")
                        onClicked: window.corner.toggleMute()
                    }

                    QQC2.Slider {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                        from: 0
                        to: 100
                        stepSize: 5
                        value: window.corner.volume
                        Accessible.name: KI18n.i18nc("@label:slider", "Volume")
                        onMoved: window.corner.setVolume(value)
                    }
                }
            }
        }

        // The layout's short name, such as GB; clicking switches to the next one.
        QQC2.ToolButton {
            visible: window.corner.layout.length > 0
            text: window.corner.layout.toUpperCase()
            font.weight: Font.DemiBold
            enabled: window.corner.layoutCount > 1
            QQC2.ToolTip.text: window.corner.layoutCount > 1
                ? KI18n.i18nc("@info:tooltip %1 is a keyboard layout's name", "Keyboard: %1. Click to switch layouts.", window.corner.layoutName)
                : KI18n.i18nc("@info:tooltip %1 is a keyboard layout's name", "Keyboard: %1", window.corner.layoutName)
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            Accessible.name: QQC2.ToolTip.text
            onClicked: window.corner.nextLayout()
        }
    }
}
