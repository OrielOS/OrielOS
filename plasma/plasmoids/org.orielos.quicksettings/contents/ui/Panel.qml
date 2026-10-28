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

// Sill's Quick Settings: what's playing on a card of its own, then the card with the tiles, the
// brightness and volume sliders, and the footer with the battery, 12 px apart, with the same gap to
// the taskbar under them and to the screen's edge beside them, left clear.
Item {
    id: panel

    required property var quickSettings

    readonly property int inset: 20
    readonly property int gap: panel.quickSettings.gap
    readonly property var player: panel.quickSettings.media.currentPlayer

    width: cards.width + panel.gap
    height: cards.implicitHeight + panel.gap

    function timeString(msecSinceEpoch: real): string {
        return new Date(msecSinceEpoch).toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
    }

    ColumnLayout {
        id: cards

        width: 3 * 107 + 2 * 10 + 2 * panel.inset
        spacing: panel.gap

        MediaCard {
            Layout.fillWidth: true
            visible: panel.player !== null && (panel.player?.track ?? "").length > 0
            player: panel.player
        }

        Card {
            Layout.fillWidth: true
            // A sub-page takes the settings' place at the same height, or a little more for a short
            // list of tiles, and scrolls what doesn't fit.
            implicitHeight: panel.quickSettings.page === "" ? settings.implicitHeight : Math.max(settings.implicitHeight, 380)

            ColumnLayout {
                id: settings

                anchors.left: parent.left
                anchors.right: parent.right
                visible: panel.quickSettings.page === ""
                spacing: 0

                GridLayout {
                    Layout.fillWidth: true
                    Layout.margins: panel.inset
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
                        onDetailsRequested: panel.quickSettings.page = "wifi"
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
                        onDetailsRequested: panel.quickSettings.page = "bluetooth"
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
                        onClicked: panel.quickSettings.page = "sound"
                    }
                }

                PanelFooter {
                    Layout.fillWidth: true
                    quickSettings: panel.quickSettings
                    inset: panel.inset
                }
            }

            Loader {
                id: subPage

                anchors.fill: parent
                active: panel.quickSettings.page !== ""
                focus: active
                sourceComponent: {
                    switch (panel.quickSettings.page) {
                    case "wifi":
                        return wifiPage;
                    case "bluetooth":
                        return bluetoothPage;
                    case "sound":
                        return soundPage;
                    }
                    return null;
                }
            }
        }
    }

    Component {
        id: wifiPage
        WifiPage {
            quickSettings: panel.quickSettings
            inset: panel.inset
            focus: true
            onBack: panel.quickSettings.page = ""
        }
    }

    Component {
        id: bluetoothPage
        BluetoothPage {
            quickSettings: panel.quickSettings
            inset: panel.inset
            focus: true
            onBack: panel.quickSettings.page = ""
        }
    }

    Component {
        id: soundPage
        SoundPage {
            quickSettings: panel.quickSettings
            inset: panel.inset
            focus: true
            onBack: panel.quickSettings.page = ""
        }
    }
}
