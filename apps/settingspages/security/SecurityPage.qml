// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// Device security: whether this start meets each requirement of games with anti-cheat, with what
// to do about any that isn't met.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property DeviceSecurity security: DeviceSecurity {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }
    readonly property bool checked: root.security.checks.length > 0

    // Settings names the page above it, so the page's own title bar would only repeat the name.
    // System Settings has no such heading, so the title bar stays there.
    Component.onCompleted: {
        if (Qt.application.name === "orielos-settings") {
            globalToolBarStyle = Kirigami.ApplicationHeaderStyle.None;
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 3
            text: root.l10n.i18nc("@title:group", "Protection")
        }

        Repeater {
            model: root.security.protection

            delegate: RowLayout {
                id: protectionRow

                required property var modelData

                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    Layout.alignment: Qt.AlignTop
                    source: protectionRow.modelData.result === "met" ? "data-success" : protectionRow.modelData.result === "not-met" ? "data-warning" : "data-information"
                    Accessible.ignored: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        Layout.fillWidth: true
                        level: 4
                        textFormat: Text.PlainText
                        text: protectionRow.modelData.title
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: protectionRow.modelData.explanation
                    }
                }
            }
        }

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 3
            text: root.l10n.i18nc("@title:group", "Games with anti-cheat")
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.l10n.i18nc("@info", "Games with anti-cheat, such as those using Easy Anti-Cheat, check that the PC started in a locked-down, trusted way. OrielOS always starts like that, as long as the PC's firmware allows it.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.checked && !root.security.running
            type: root.security.allMet ? Kirigami.MessageType.Positive : Kirigami.MessageType.Warning
            text: root.security.allMet
                ? root.l10n.i18nc("@info", "This PC meets every requirement of games with anti-cheat.")
                : root.l10n.i18nc("@info", "This PC doesn't meet every requirement, so some games with anti-cheat may not start. See below for what to change.")
        }

        QQC2.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.checked
            running: visible
        }

        Repeater {
            model: root.security.checks

            delegate: RowLayout {
                id: row

                required property var modelData
                readonly property string result: row.modelData.result

                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    Layout.alignment: Qt.AlignTop
                    source: row.result === "met" ? "data-success" : row.result === "not-met" ? "data-warning" : "data-information"
                    Accessible.ignored: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        Layout.fillWidth: true
                        level: 4
                        textFormat: Text.PlainText
                        text: row.result === "met"
                            ? root.l10n.i18nc("@title %1 is a requirement, such as Secure Boot", "%1: met", row.modelData.title)
                            : row.result === "not-met"
                                ? root.l10n.i18nc("@title %1 is a requirement, such as Secure Boot", "%1: not met", row.modelData.title)
                                : root.l10n.i18nc("@title %1 is a requirement, such as Secure Boot", "%1: couldn't check", row.modelData.title)
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: row.modelData.explanation
                    }
                }
            }
        }

        QQC2.Button {
            text: root.l10n.i18nc("@action:button", "Check again")
            icon.name: "view-refresh"
            enabled: !root.security.running
            onClicked: root.security.run()
        }
    }
}
