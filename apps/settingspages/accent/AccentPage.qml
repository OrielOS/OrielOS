// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The accent colour of highlights, selected items and focus rings. Light and dark mode are on the
// Themes page; the accent carries over between them.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property AccentColour accent: AccentColour {}
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

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.l10n.i18nc("@info", "Choose the colour of highlights, selected items and focus rings. Light and dark mode are on the Themes page.")
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Accessible.role: Accessible.Grouping
            Accessible.name: root.l10n.i18nc("@label", "Accent colour")

            Repeater {
                model: root.accent.choices

                delegate: T.AbstractButton {
                    id: swatch

                    required property var modelData
                    readonly property bool chosen: root.accent.current.valid && Qt.colorEqual(root.accent.current, swatch.modelData.colour)

                    implicitWidth: Kirigami.Units.gridUnit * 2.5
                    implicitHeight: Kirigami.Units.gridUnit * 2.5
                    enabled: !root.accent.busy
                    activeFocusOnTab: true
                    hoverEnabled: true

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: swatch.modelData.name
                    Accessible.checked: swatch.chosen

                    QQC2.ToolTip.text: swatch.modelData.name
                    QQC2.ToolTip.visible: swatch.hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

                    background: Rectangle {
                        radius: width / 2
                        color: swatch.modelData.colour
                        border.width: swatch.visualFocus || swatch.chosen ? 3 : 0
                        border.color: Kirigami.Theme.textColor
                    }

                    contentItem: Kirigami.Icon {
                        source: "checkmark"
                        color: "white"
                        isMask: true
                        visible: swatch.chosen
                    }

                    onClicked: root.accent.choose(swatch.modelData.colour)
                }
            }
        }

        QQC2.Button {
            text: root.l10n.i18nc("@action:button", "Use the theme's colour")
            icon.name: "edit-undo"
            enabled: !root.accent.busy && root.accent.current.valid
            onClicked: root.accent.useThemeColour()
        }

        QQC2.Switch {
            text: root.l10n.i18nc("@option:check", "Show accent colour on Start and taskbar")
            checked: root.accent.accentOnTaskbar
            onToggled: {
                root.accent.accentOnTaskbar = checked;
                checked = Qt.binding(() => root.accent.accentOnTaskbar);
            }
        }

        QQC2.Switch {
            text: root.l10n.i18nc("@option:check", "Transparency effects")
            checked: root.accent.transparency
            onToggled: {
                root.accent.transparency = checked;
                checked = Qt.binding(() => root.accent.transparency);
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@info", "The taskbar, Start and other pop-ups show the blurred desktop through them. Off, they're solid.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.accent.error.length > 0
            type: Kirigami.MessageType.Error
            text: root.accent.error
        }

        // Related settings, as Windows lists them at the foot of a page.
        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.gridUnit
            level: 4
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@title:group", "Related settings")
        }

        Repeater {
            model: [
                { page: "themes", text: root.l10n.i18nc("@action:button A related Settings page", "Themes") },
                { page: "background", text: root.l10n.i18nc("@action:button A related Settings page", "Background") },
            ]

            delegate: Kirigami.LinkButton {
                id: related

                required property var modelData

                text: related.modelData.text
                onClicked: Qt.openUrlExternally("orielos-settings:" + related.modelData.page)
            }
        }
    }
}
