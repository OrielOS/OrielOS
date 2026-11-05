// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Date & time: the clock, large, then whether network time keeps it right and whether the time zone
// follows this PC's location, the time zone, and Sync now with when the clock was last
// synchronised. Each change applies at once; choosing a time zone or setting the time by hand is in
// Plasma's clock settings, one link away.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property DateTimeSettings clock: DateTimeSettings {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
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

        // The clock. Figures of one width, so the time doesn't shift as the seconds change.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                text: root.clock.time
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 3
                font.features: { "tnum": 1 }
                textFormat: Text.PlainText
                Accessible.name: root.l10n.i18nc("@info:whatsthis %1 is a time, %2 a date", "The time is %1 on %2", root.clock.time, root.clock.date)
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: root.clock.date
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: Kirigami.Theme.disabledTextColor
                text: root.clock.timeZone
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: text.length > 0
            type: Kirigami.MessageType.Error
            text: root.clock.error
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.Switch {
                Kirigami.FormData.label: root.l10n.i18nc("@label:checkbox", "Set time automatically:")
                text: checked ? root.l10n.i18nc("@option:check A switch's state", "On") : root.l10n.i18nc("@option:check A switch's state", "Off")
                checked: root.clock.autoTime
                enabled: root.clock.canChangeAutoTime
                onToggled: {
                    root.clock.setAutoTime(checked);
                    checked = Qt.binding(() => root.clock.autoTime);
                }
            }

            QQC2.Switch {
                Kirigami.FormData.label: root.l10n.i18nc("@label:checkbox", "Set time zone automatically:")
                text: checked ? root.l10n.i18nc("@option:check A switch's state", "On") : root.l10n.i18nc("@option:check A switch's state", "Off")
                checked: root.clock.autoTimeZone
                enabled: root.clock.canChangeAutoTimeZone
                onToggled: {
                    root.clock.setAutoTimeZone(checked);
                    checked = Qt.binding(() => root.clock.autoTimeZone);
                }
            }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                text: root.l10n.i18nc("@info", "Uses this PC's internet address to look up its time zone with Fedora's location service, after each start, every few hours and whenever it connects to a network.")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
            }

            RowLayout {
                Kirigami.FormData.label: root.l10n.i18nc("@label", "Time zone:")
                spacing: Kirigami.Units.largeSpacing

                QQC2.Label {
                    textFormat: Text.PlainText
                    text: root.clock.timeZone
                }

                QQC2.Button {
                    text: root.l10n.i18nc("@action:button Change the time zone", "&Change…")
                    enabled: !root.clock.autoTimeZone
                    onClicked: Qt.openUrlExternally("orielos-settings:date-time-more")
                }
            }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                visible: root.clock.autoTimeZone
                text: root.l10n.i18nc("@info", "To choose the time zone yourself, turn off setting it automatically.")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
            }

            Item {
                Kirigami.FormData.isSection: true
            }

            RowLayout {
                Kirigami.FormData.label: root.l10n.i18nc("@label", "Synchronise the clock:")
                spacing: Kirigami.Units.largeSpacing

                QQC2.Button {
                    text: root.l10n.i18nc("@action:button Synchronise the clock now", "&Sync now")
                    icon.name: "view-refresh"
                    enabled: root.clock.canSync
                    onClicked: root.clock.syncNow()
                }

                QQC2.BusyIndicator {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    visible: root.clock.syncing
                    running: visible
                    Accessible.name: root.l10n.i18nc("@info:status", "Synchronising")
                }

                QQC2.Label {
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 20
                    visible: !root.clock.syncing && text.length > 0
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    color: root.clock.syncFailed ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
                    text: root.clock.syncResult
                }
            }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                visible: !root.clock.autoTime
                text: root.l10n.i18nc("@info", "Turn on setting the time automatically to synchronise the clock.")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
            }

            // chronyd only runs while the time is set automatically.
            QQC2.Label {
                Kirigami.FormData.label: root.l10n.i18nc("@label", "Last synchronised:")
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                visible: root.clock.autoTime
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: root.clock.lastSync
            }
        }

        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.gridUnit
            level: 4
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@title:group", "Related settings")
        }

        Kirigami.LinkButton {
            text: root.l10n.i18nc("@action:button A related Settings page", "More date and time settings")
            onClicked: Qt.openUrlExternally("orielos-settings:date-time-more")
        }
    }
}
