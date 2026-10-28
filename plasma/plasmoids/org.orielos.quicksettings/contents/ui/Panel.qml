// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.bluezqt as BluezQt
import org.kde.kirigami as Kirigami
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.plasma.private.brightnesscontrolplugin as Brightness
import org.kde.plasma.private.volume as Volume

// Sill's Quick Settings panel: what's playing, the tiles, the brightness and volume sliders, and
// the footer with the battery.
ColumnLayout {
    id: panel

    required property var quickSettings

    // Inside the popup's own padding, which makes up the rest of Sill's 20 px.
    readonly property int inset: 9
    readonly property var player: panel.quickSettings.media.currentPlayer

    Layout.preferredWidth: 3 * 107 + 2 * 10 + 2 * inset
    Layout.minimumWidth: Layout.preferredWidth
    Layout.maximumWidth: Layout.preferredWidth
    spacing: 0

    function timeString(msecSinceEpoch: real): string {
        return new Date(msecSinceEpoch).toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
    }

    MediaCard {
        Layout.fillWidth: true
        Layout.margins: panel.inset
        Layout.bottomMargin: 0
        visible: panel.player !== null && (panel.player?.track ?? "").length > 0
        player: panel.player
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.margins: panel.inset
        Layout.topMargin: panel.inset + 4
        columns: 3
        rowSpacing: 10
        columnSpacing: 10

        Tile {
            Layout.fillWidth: true
            visible: panel.quickSettings.hasWifi
            text: i18nc("@action:button", "Wi-Fi")
            iconName: checked ? "network-wireless-on" : "network-wireless-off"
            status: checked ? (panel.quickSettings.wifiName || i18nc("@info:status Wi-Fi is on but not connected", "Not connected")) : ""
            checked: panel.quickSettings.enabledConnections.wirelessEnabled
            enabled: !PlasmaNM.Configuration.airplaneModeEnabled && panel.quickSettings.enabledConnections.wirelessHwEnabled
            hasDetails: true
            onClicked: panel.quickSettings.networkHandler.enableWireless(!checked)
            onDetailsRequested: panel.quickSettings.openSettings("network")
        }

        Tile {
            Layout.fillWidth: true
            visible: panel.quickSettings.hasBluetooth
            text: i18nc("@action:button", "Bluetooth")
            iconName: checked ? "network-bluetooth" : "network-bluetooth-inactive"
            readonly property int connected: BluezQt.Manager.connectedDevices.length
            status: checked && connected > 0 ? i18ncp("@info:status", "%1 connected", "%1 connected", connected) : ""
            checked: BluezQt.Manager.bluetoothOperational
            hasDetails: true
            onClicked: panel.quickSettings.setBluetoothEnabled(!checked)
            onDetailsRequested: panel.quickSettings.openSettings("bluetooth")
        }

        Tile {
            Layout.fillWidth: true
            visible: panel.quickSettings.hasWifi
            text: i18nc("@action:button", "Airplane mode")
            iconName: "network-flightmode-on"
            checked: PlasmaNM.Configuration.airplaneModeEnabled
            onClicked: {
                const enable = !checked;
                panel.quickSettings.networkHandler.enableAirplaneMode(enable);
                PlasmaNM.Configuration.airplaneModeEnabled = enable;
            }
        }

        Tile {
            Layout.fillWidth: true
            visible: panel.quickSettings.powerProfiles.profiles.includes("power-saver")
            text: i18nc("@action:button", "Energy saver")
            iconName: "orielos-energy-saver-symbolic"
            checked: panel.quickSettings.powerProfiles.activeProfile === "power-saver"
            onClicked: {
                const profiles = panel.quickSettings.powerProfiles;
                profiles.setProfile(checked ? (profiles.configuredProfile && profiles.configuredProfile !== "power-saver" ? profiles.configuredProfile : "balanced") : "power-saver");
            }
        }

        Tile {
            Layout.fillWidth: true
            readonly property var nightLight: panel.quickSettings.nightLight
            visible: nightLight.available
            text: i18nc("@action:button", "Night light")
            iconName: "orielos-night-light-symbolic"
            checked: nightLight.on
            status: {
                if (!checked || !nightLight.running || nightLight.nextChange <= 0) {
                    return "";
                }
                return nightLight.daylight
                    ? i18nc("@info:status %1 is a time", "From %1", panel.timeString(nightLight.nextChange))
                    : i18nc("@info:status %1 is a time", "Until %1", panel.timeString(nightLight.nextChange));
            }
            onClicked: {
                if (!nightLight.enabled) {
                    panel.quickSettings.openSettings("night-light");
                } else {
                    Brightness.NightLightInhibitor.toggleInhibition();
                }
            }
        }

        Tile {
            Layout.fillWidth: true
            text: i18nc("@action:button", "Accessibility")
            iconName: "orielos-accessibility-symbolic"
            onClicked: panel.quickSettings.openSettings("accessibility")
        }
    }

    // Brightness of the first screen that has it, as Windows shows one slider.
    Repeater {
        model: panel.quickSettings.screenBrightness.isBrightnessAvailable ? panel.quickSettings.screenBrightness.displays : null

        delegate: SliderRow {
            id: brightnessRow

            required property int index
            required property string displayName
            required property int brightness
            required property int maxBrightness

            Layout.fillWidth: true
            Layout.leftMargin: panel.inset
            Layout.rightMargin: panel.inset
            Layout.topMargin: 6
            visible: index === 0
            iconName: "brightness-high"
            accessibleName: i18nc("@label:slider", "Brightness")
            from: 0
            to: maxBrightness
            stepSize: 1
            value: brightness
            onMoved: value => panel.quickSettings.screenBrightness.setBrightness(brightnessRow.displayName, Math.round(value))
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: panel.inset
        Layout.rightMargin: panel.inset
        Layout.topMargin: 10
        Layout.bottomMargin: panel.inset + 6
        visible: panel.quickSettings.hasSink
        spacing: 12

        SliderRow {
            Layout.fillWidth: true
            iconName: panel.quickSettings.volumeIcon
            accessibleName: i18nc("@label:slider", "Volume")
            from: 0
            to: 100
            stepSize: panel.quickSettings.volumeStep
            value: panel.quickSettings.volumePercent
            onMoved: value => {
                const sink = panel.quickSettings.sink;
                sink.muted = false;
                sink.volume = Math.round(value / 100 * Volume.PulseAudio.NormalVolume);
            }
            onIconClicked: panel.quickSettings.sink.muted = !panel.quickSettings.sink.muted
        }

        MediaButton {
            round: true
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            iconName: "orielos-headphones-symbolic"
            accessibleName: i18nc("@action:button", "Sound output")
            onClicked: panel.quickSettings.openSettings("sound")
        }
    }

    PanelFooter {
        Layout.fillWidth: true
        quickSettings: panel.quickSettings
        inset: panel.inset
    }
}
