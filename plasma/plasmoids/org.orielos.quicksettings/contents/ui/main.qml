// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// Quick Settings, on the taskbar between the hidden icons and the clock: one button showing the
// network, volume and battery, which opens Sill's panel of what's playing, tiles for Wi-Fi,
// Bluetooth, airplane mode, energy saver, night light and accessibility, brightness and volume
// sliders, and the battery. Plasma's own widgets for these stay in the hidden icons; this one uses
// the same Plasma services they do.

import QtQuick
import org.kde.bluezqt as BluezQt
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.plasma.plasmoid
import org.kde.plasma.private.battery as Battery
import org.kde.plasma.private.batterymonitor as Power
import org.kde.plasma.private.brightnesscontrolplugin as Brightness
import org.kde.plasma.private.mpris as Mpris
import org.kde.plasma.private.volume as Volume
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: root

    // Whether the panel is open, and which sub-page it shows: "" for the tiles, or "wifi",
    // "bluetooth" or "sound".
    property bool open: false
    property string page: ""
    // Whether the tiles are being edited: unpinned, added back and put in a new order.
    property bool editing: false
    // The tiles shown, in order; Edit changes them through setTiles().
    readonly property var configuredTiles: Plasmoid.configuration.tiles

    function setTiles(ids: var) {
        Plasmoid.configuration.tiles = ids;
    }
    // The gap Sill leaves between the taskbar, or the screen's edge, and the cards.
    readonly property int gap: 12

    // Volume moves 2 % a step, from the wheel and from the slider.
    readonly property int volumeStep: 2

    readonly property var sink: Volume.PreferredDevice.sink
    readonly property bool hasSink: sink !== null && sink.name !== "auto_null"
    readonly property int volumePercent: hasSink ? Math.round(sink.volume / Volume.PulseAudio.NormalVolume * 100) : 0
    readonly property string volumeIcon: hasSink ? Volume.AudioIcon.forVolume(volumePercent, sink.muted, "") : "audio-volume-muted"

    readonly property bool hasBattery: battery.hasInternalBatteries
    readonly property string batteryIcon: {
        const level = Math.min(100, Math.round(battery.percent / 10) * 10);
        const charging = battery.pluggedIn && battery.state === Battery.BatteryControlModel.Charging;
        return "battery-" + String(level).padStart(3, "0") + (charging ? "-charging" : "");
    }

    readonly property string networkIcon: connectionIcon.connectionIcon + "-symbolic"
    readonly property bool hasWifi: availableDevices.wirelessDeviceAvailable
    property string wifiName: ""
    readonly property bool hasBluetooth: BluezQt.Manager.bluetoothBlocked || BluezQt.Manager.adapters.length > 0

    function changeVolume(steps: int) {
        if (!root.hasSink) {
            return;
        }
        const percent = Math.max(0, Math.min(100, root.volumePercent + steps * root.volumeStep));
        root.sink.muted = false;
        root.sink.volume = Math.round(percent / 100 * Volume.PulseAudio.NormalVolume);
    }

    function setBluetoothEnabled(enable: bool) {
        BluezQt.Manager.bluetoothBlocked = !enable;
        BluezQt.Manager.adapters.forEach(adapter => {
            adapter.powered = enable;
        });
    }

    // Opens a page of OrielOS's Settings, or Settings itself without one.
    function openSettings(page: string) {
        root.open = false;
        Qt.openUrlExternally("orielos-settings:" + page);
    }

    Plasmoid.icon: root.networkIcon
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    toolTipMainText: Plasmoid.title
    toolTipSubText: {
        const lines = [networkStatus.activeConnections];
        if (root.hasSink) {
            lines.push(i18nc("@info:tooltip", "Volume %1%", root.volumePercent));
        }
        if (root.hasBattery) {
            lines.push(i18nc("@info:tooltip", "Battery %1%", battery.percent));
        }
        return lines.filter(line => line.length > 0).join("\n");
    }

    // Sill draws what's playing and the settings as two cards with a gap. Plasma's popups for
    // taskbar widgets always draw one pane, so the button is the full representation and the panel
    // is a window of this widget's own, with no pane, in which the cards are drawn.
    preferredRepresentation: fullRepresentation
    fullRepresentation: CompactButton {
        quickSettings: root
    }

    Plasmoid.onActivated: root.open = !root.open

    PlasmaCore.Dialog {
        id: panelWindow

        visualParent: root.fullRepresentationItem
        location: PlasmaCore.Types.BottomEdge
        type: PlasmaCore.Dialog.AppletPopup
        flags: Qt.WindowStaysOnTopHint
        backgroundHints: PlasmaCore.Dialog.NoBackground
        hideOnWindowDeactivate: true
        visible: root.open

        onVisibleChanged: {
            if (visible) {
                panelWindow.requestActivate();
            } else {
                root.open = false;
                root.page = "";
                root.editing = false;
            }
        }

        mainItem: Panel {
            quickSettings: root
            focus: true
            Keys.onEscapePressed: root.open = false
        }
    }

    // Network: Plasma's network applet's services.
    PlasmaNM.EnabledConnections {
        id: enabledConnections
    }
    PlasmaNM.AvailableDevices {
        id: availableDevices
    }
    PlasmaNM.NetworkStatus {
        id: networkStatus
    }
    PlasmaNM.ConnectionIcon {
        id: connectionIcon
        connectivity: networkStatus.connectivity
    }
    PlasmaNM.Handler {
        id: networkHandler
    }
    // Every connection and network in range, for the Wi-Fi tile and the Wi-Fi page.
    PlasmaNM.NetworkModel {
        id: networkModel
    }
    // The Wi-Fi network in use, for the Wi-Fi tile.
    KItemModels.KSortFilterProxyModel {
        id: activeWifi
        sourceModel: networkModel
        // A change of state filters the row again.
        filterRoleName: "ConnectionState"
        filterRowCallback: (row, parent) => {
            const model = activeWifi.sourceModel;
            const index = model.index(row, 0, parent);
            const roles = model.KItemModels.KRoleNames;
            return model.data(index, roles.role("ConnectionState")) === PlasmaNM.Enums.Activated
                && model.data(index, roles.role("Type")) === PlasmaNM.Enums.Wireless;
        }
        onCountChanged: root.wifiName = count > 0 ? String(data(index(0, 0), Qt.DisplayRole) ?? "") : ""
        onDataChanged: root.wifiName = count > 0 ? String(data(index(0, 0), Qt.DisplayRole) ?? "") : ""
    }

    // Battery and energy saver: Plasma's power applet's services.
    Battery.BatteryControlModel {
        id: battery
    }
    Power.PowerProfilesControl {
        id: powerProfiles
    }

    // Brightness and night light: Plasma's brightness applet's services.
    Brightness.ScreenBrightnessControl {
        id: screenBrightness
        isSilent: root.open
    }
    DBus.Properties {
        id: nightLight
        busType: DBus.BusType.Session
        service: "org.kde.KWin.NightLight"
        path: "/org/kde/KWin/NightLight"
        iface: "org.kde.KWin.NightLight"

        readonly property bool available: Boolean(properties.available)
        readonly property bool enabled: Boolean(properties.enabled)
        readonly property bool running: Boolean(properties.running)
        readonly property bool inhibited: Boolean(properties.inhibited)
        readonly property bool inhibitedHere: Brightness.NightLightInhibitor.inhibited
        readonly property bool daylight: Boolean(properties.daylight)
        readonly property double nextChange: Number(properties.scheduledTransitionDateTime) * 1000
        // On means it's set up and not paused from here; it may still be waiting for the evening.
        readonly property bool on: enabled && (!inhibited || !inhibitedHere)
    }

    // What's playing.
    Mpris.Mpris2Model {
        id: media
    }

    // The panel's parts read these through quickSettings.
    readonly property alias enabledConnections: enabledConnections
    readonly property alias networkHandler: networkHandler
    readonly property alias networkModel: networkModel
    readonly property alias battery: battery
    readonly property alias powerProfiles: powerProfiles
    readonly property alias screenBrightness: screenBrightness
    readonly property alias nightLight: nightLight
    readonly property alias media: media
}
