/*
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: GPL-3.0-or-later
*/

// The quick status at the bottom right of the idle lock screen, as in Sill's lock screen: for each
// app that sent notifications since the screen locked, its icon and how many; then the network and
// the battery's charge. The notifications come from Plasma's notification server, which passes
// each new one to watchers such as this screen and tells them when an app withdraws one.

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.plasma.private.battery as Battery

RowLayout {
    id: quickStatus

    property color color: "#FFFFFF"
    // At most this many apps show, those with the most notifications first.
    property int maximumApps: 3

    // [{ key, iconName, name, count }], rebuilt whenever a notification arrives or goes.
    property var apps: []

    spacing: 18

    function rebuild() {
        const byApp = new Map();
        for (let i = 0; i < notificationEntries.count; ++i) {
            const entry = notificationEntries.objectAt(i);
            if (!entry) {
                continue;
            }
            const key = entry.desktopEntry || entry.applicationName;
            const app = byApp.get(key) ?? { key, iconName: entry.applicationIconName, name: entry.applicationName, count: 0 };
            app.count += 1;
            byApp.set(key, app);
        }
        quickStatus.apps = Array.from(byApp.values())
            .sort((a, b) => b.count - a.count)
            .slice(0, quickStatus.maximumApps);
    }

    NotificationManager.WatchedNotificationsModel {
        id: watchedNotifications
    }

    Instantiator {
        id: notificationEntries
        model: watchedNotifications
        delegate: QtObject {
            required property string applicationName
            required property string applicationIconName
            required property string desktopEntry
        }
        onObjectAdded: quickStatus.rebuild()
        onObjectRemoved: Qt.callLater(quickStatus.rebuild)
    }

    PlasmaNM.NetworkStatus {
        id: networkStatus
    }
    PlasmaNM.ConnectionIcon {
        id: connectionIcon
        connectivity: networkStatus.connectivity
    }

    Battery.BatteryControlModel {
        id: battery
    }

    Repeater {
        model: quickStatus.apps

        delegate: RowLayout {
            required property var modelData
            spacing: 6
            Accessible.role: Accessible.StaticText
            Accessible.name: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status app name, number of notifications", "%1: %2 new", modelData.name, modelData.count)

            // The app's line icon in the status colour, as Sill draws it, or its full-colour icon
            // when the theme has no line icon for it (a full-colour icon as a mask is a blob).
            Kirigami.Icon {
                id: symbolicIcon
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                visible: valid
                source: (modelData.iconName || "preferences-desktop-notification-bell") + "-symbolic"
                isMask: true
                color: quickStatus.color
            }
            Kirigami.Icon {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                visible: !symbolicIcon.valid
                source: modelData.iconName
                fallback: "preferences-desktop-notification-bell-symbolic"
            }
            PlasmaComponents3.Label {
                text: modelData.count > 99 ? "99+" : String(modelData.count)
                textFormat: Text.PlainText
                color: quickStatus.color
                font.pixelSize: 13
            }
        }
    }

    Kirigami.Icon {
        Layout.preferredWidth: 18
        Layout.preferredHeight: 18
        visible: connectionIcon.connectionIcon !== ""
        source: connectionIcon.connectionIcon + "-symbolic"
        isMask: true
        color: quickStatus.color
        Accessible.role: Accessible.StaticText
        Accessible.name: networkStatus.activeConnections
    }

    RowLayout {
        visible: battery.hasInternalBatteries
        spacing: 6
        Accessible.role: Accessible.StaticText
        Accessible.name: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Battery at %1%", battery.percent)

        Kirigami.Icon {
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            source: {
                const level = Math.min(100, Math.round(battery.percent / 10) * 10);
                const charging = battery.pluggedIn && battery.state === Battery.BatteryControlModel.Charging;
                return "battery-" + String(level).padStart(3, "0") + (charging ? "-charging" : "") + "-symbolic";
            }
            isMask: true
            color: quickStatus.color
        }
        PlasmaComponents3.Label {
            text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status battery charge", "%1%", battery.percent)
            textFormat: Text.PlainText
            color: quickStatus.color
            font.pixelSize: 13
        }
    }
}
