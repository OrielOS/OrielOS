// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The location-in-use icon, as Windows shows an arrow in the tray: hidden until an app uses the
// computer's location through GeoClue (its manager's InUse), then shown in the system tray, with
// a tooltip saying so; clicking it says the same, with a way to Settings' app permissions. GeoClue
// starts when an app asks and stops when it's idle, each time under a new D-Bus name, so the
// properties are read afresh whenever it starts.

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import org.kde.plasma.components as PC3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: root

    readonly property bool inUse: geoclue.item !== null && (geoclue.item as DBus.Properties).properties.InUse === true

    DBus.DBusServiceWatcher {
        id: service

        busType: DBus.BusType.System
        watchedService: "org.freedesktop.GeoClue2"
    }

    Loader {
        id: geoclue

        active: service.registered
        sourceComponent: DBus.Properties {
            busType: DBus.BusType.System
            service: "org.freedesktop.GeoClue2"
            path: "/org/freedesktop/GeoClue2/Manager"
            iface: "org.freedesktop.GeoClue2.Manager"
        }
    }

    Plasmoid.status: root.inUse ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
    Plasmoid.icon: "mark-location"
    toolTipMainText: KI18n.i18nc("@info:tooltip", "Location in use")
    toolTipSubText: KI18n.i18nc("@info:tooltip", "An app is using this computer's location.")

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        spacing: Kirigami.Units.largeSpacing

        PC3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.inUse ? KI18n.i18nc("@info", "An app is using this computer's location.") : KI18n.i18nc("@info", "No app is using this computer's location.")
        }

        PC3.Button {
            Layout.alignment: Qt.AlignRight
            text: KI18n.i18nc("@action:button", "App permissions")
            icon.name: "preferences-desktop-user-password"
            onClicked: Qt.openUrlExternally("orielos-settings:kcm_app-permissions")
        }
    }
}
