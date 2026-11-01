// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Do not disturb at set times, as Windows' Notifications › Turn on do not disturb automatically
// offers. Each change applies at once.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property DndSchedule schedule: DndSchedule {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }
    // The times to choose from, every quarter of an hour, in minutes after midnight.
    readonly property list<int> times: Array.from({ length: 96 }, (_, step) => step * 15)

    function timeText(minutes: int): string {
        const time = new Date(2000, 0, 1, Math.floor(minutes / 60), minutes % 60);
        return time.toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
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

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.Switch {
                Kirigami.FormData.label: root.l10n.i18nc("@option:check", "Turn on do not disturb automatically:")
                text: root.schedule.enabled ? root.l10n.i18nc("@option:check A switch's state", "On") : root.l10n.i18nc("@option:check A switch's state", "Off")
                checked: root.schedule.enabled
                onToggled: {
                    root.schedule.enabled = checked;
                    checked = Qt.binding(() => root.schedule.enabled);
                }
            }

            QQC2.ComboBox {
                id: from

                Kirigami.FormData.label: root.l10n.i18nc("@label:listbox The time do not disturb starts", "From:")
                enabled: root.schedule.enabled
                model: root.times.map(minutes => root.timeText(minutes))
                // A time set elsewhere that isn't on a quarter hour shows the quarter before it.
                currentIndex: Math.floor(root.schedule.from / 15)
                onActivated: index => {
                    root.schedule.from = root.times[index];
                    currentIndex = Qt.binding(() => Math.floor(root.schedule.from / 15));
                }
            }

            QQC2.ComboBox {
                id: to

                Kirigami.FormData.label: root.l10n.i18nc("@label:listbox The time do not disturb ends", "To:")
                enabled: root.schedule.enabled
                model: from.model
                currentIndex: Math.floor(root.schedule.to / 15)
                onActivated: index => {
                    root.schedule.to = root.times[index];
                    currentIndex = Qt.binding(() => Math.floor(root.schedule.to / 15));
                }
            }

            QQC2.ComboBox {
                Kirigami.FormData.label: root.l10n.i18nc("@label:listbox Which days do not disturb turns on", "Repeats:")
                enabled: root.schedule.enabled
                model: [
                    root.l10n.i18nc("@item:inlistbox Do not disturb repeats", "Daily"),
                    root.l10n.i18nc("@item:inlistbox Do not disturb repeats", "Weekdays"),
                    root.l10n.i18nc("@item:inlistbox Do not disturb repeats", "Weekends"),
                ]
                currentIndex: root.schedule.days
                onActivated: index => {
                    root.schedule.days = index;
                    currentIndex = Qt.binding(() => root.schedule.days);
                }
            }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                visible: root.schedule.enabled && root.schedule.from === root.schedule.to
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: root.l10n.i18nc("@info", "Choose an end time that's different from the start time.")
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            opacity: 0.75
            text: root.l10n.i18nc("@info", "Notifications still go to the notification centre while do not disturb is on. Hours that start late in the evening end the next morning.")
        }

        // Related settings, as Windows lists them at the foot of a page.
        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.gridUnit
            level: 4
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@title:group", "Related settings")
        }

        Kirigami.LinkButton {
            text: root.l10n.i18nc("@action:button A related Settings page", "Notifications")
            onClicked: Qt.openUrlExternally("orielos-settings:notifications")
        }
    }
}
