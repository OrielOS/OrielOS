// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.bluezqt as BluezQt
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.brightnesscontrolplugin as Brightness
import org.kde.plasma.workspace.keyboardlayout as Keyboards

// Quick Settings' tiles, three across, in the order the user chose. While Quick Settings is being
// edited, each tile has a button to unpin it and can be dragged to a new place, and clicking a tile
// no longer changes the setting; Edit's Add puts unpinned tiles back at the end. Six tiles fit on a
// page; more go onto further pages, turned with the dots under the grid (Panel.qml).
GridLayout {
    id: grid

    required property var quickSettings

    // Every tile Quick Settings has, in its first order.
    readonly property var allTiles: ["wifi", "bluetooth", "airplane-mode", "energy-saver", "night-light", "accessibility",
        "mobile-hotspot", "project", "keyboard-layout"]
    readonly property int tilesPerPage: 6
    // The page of tiles showing; every tile shows while editing.
    property int page: 0
    readonly property int pageCount: Math.max(1, Math.ceil(tiles.count / tilesPerPage))
    onPageCountChanged: page = Math.min(page, pageCount - 1)
    // The tiles not shown, which Add offers.
    readonly property var unpinned: {
        const shown = grid.shownIds;
        return grid.allTiles.filter(id => !shown.includes(id));
    }
    property var shownIds: []

    function tileName(id: string): string {
        switch (id) {
        case "wifi":
            return i18nc("@action:button", "Wi-Fi");
        case "bluetooth":
            return i18nc("@action:button", "Bluetooth");
        case "airplane-mode":
            return i18nc("@action:button", "Airplane mode");
        case "energy-saver":
            return i18nc("@action:button", "Energy saver");
        case "night-light":
            return i18nc("@action:button", "Night light");
        case "accessibility":
            return i18nc("@action:button", "Accessibility");
        case "mobile-hotspot":
            return i18nc("@action:button", "Mobile hotspot");
        case "project":
            return i18nc("@action:button Show the screen on another display", "Project");
        case "keyboard-layout":
            return i18nc("@action:button", "Keyboard layout");
        }
        return id;
    }

    function load() {
        const ids = Array.from(grid.quickSettings.configuredTiles).map(String).filter(id => grid.allTiles.includes(id));
        tiles.clear();
        ids.forEach(id => tiles.append({ tileId: id }));
        grid.shownIds = ids;
    }

    function save() {
        const ids = [];
        for (let i = 0; i < tiles.count; ++i) {
            ids.push(tiles.get(i).tileId);
        }
        grid.shownIds = ids;
        grid.quickSettings.setTiles(ids);
    }

    function unpin(index: int) {
        tiles.remove(index);
        grid.save();
    }

    function pin(id: string) {
        tiles.append({ tileId: id });
        grid.save();
    }

    function move(from: int, to: int) {
        if (from !== to && to >= 0 && to < tiles.count) {
            tiles.move(from, to, 1);
            grid.save();
        }
    }

    columns: 3
    rowSpacing: 10
    columnSpacing: 10

    Component.onCompleted: grid.load()

    ListModel {
        id: tiles
    }

    Repeater {
        id: repeater

        model: tiles

        delegate: Item {
            id: slot

            required property int index
            required property string tileId

            Layout.fillWidth: true
            Layout.preferredHeight: 76
            implicitWidth: 107
            // A tile whose hardware isn't there (no Wi-Fi, say) takes no place, except while editing;
            // nor do tiles on other pages.
            visible: grid.quickSettings.editing
                || (((loader.item as Tile)?.available ?? true) && Math.floor(slot.index / grid.tilesPerPage) === grid.page)

            Loader {
                id: loader

                anchors.fill: parent
                sourceComponent: {
                    switch (slot.tileId) {
                    case "wifi":
                        return wifiTile;
                    case "bluetooth":
                        return bluetoothTile;
                    case "airplane-mode":
                        return airplaneTile;
                    case "energy-saver":
                        return energySaverTile;
                    case "night-light":
                        return nightLightTile;
                    case "accessibility":
                        return accessibilityTile;
                    case "mobile-hotspot":
                        return hotspotTile;
                    case "project":
                        return projectTile;
                    case "keyboard-layout":
                        return keyboardTile;
                    }
                    return null;
                }
            }

            // While editing: drag the tile to a new place; clicking it does nothing.
            MouseArea {
                id: dragArea

                anchors.fill: parent
                visible: grid.quickSettings.editing
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                Accessible.ignored: true

                onPositionChanged: mouse => {
                    if (!pressed) {
                        return;
                    }
                    const point = dragArea.mapToItem(grid, mouse.x, mouse.y);
                    for (let i = 0; i < repeater.count; ++i) {
                        const other = repeater.itemAt(i);
                        if (other && other !== slot && other.visible && other.contains(other.mapFromItem(grid, point.x, point.y))) {
                            grid.move(slot.index, i);
                            return;
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 6
                visible: dragArea.pressed
                color: "transparent"
                border.width: 2
                border.color: Kirigami.Theme.highlightColor
            }

            // While editing, the tile's unpin button, a round badge on its top right corner.
            MouseArea {
                id: unpinButton

                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -6
                anchors.topMargin: -6
                width: 22
                height: 22
                visible: grid.quickSettings.editing
                hoverEnabled: true
                activeFocusOnTab: visible
                Accessible.role: Accessible.Button
                Accessible.name: i18nc("@action:button %1 is a Quick Settings tile", "Unpin %1", grid.tileName(slot.tileId))
                onClicked: grid.unpin(slot.index)
                Keys.onSpacePressed: grid.unpin(slot.index)
                Keys.onReturnPressed: grid.unpin(slot.index)

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Qt.lighter(Kirigami.Theme.backgroundColor, unpinButton.containsMouse ? 1.9 : 1.5)
                    border.width: unpinButton.activeFocus ? 2 : 1
                    border.color: unpinButton.activeFocus ? Kirigami.Theme.focusColor
                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    source: "window-unpin"
                    isMask: true
                    color: Kirigami.Theme.textColor
                }
            }
        }
    }

    Component {
        id: wifiTile

        Tile {
            available: grid.quickSettings.hasWifi
            text: grid.tileName("wifi")
            iconName: checked ? "network-wireless-on" : "network-wireless-off"
            status: checked ? (grid.quickSettings.wifiName || i18nc("@info:status Wi-Fi is on but not connected", "Not connected")) : ""
            checked: grid.quickSettings.enabledConnections.wirelessEnabled
            enabled: grid.quickSettings.editing || (!PlasmaNM.Configuration.airplaneModeEnabled && grid.quickSettings.enabledConnections.wirelessHwEnabled)
            hasDetails: true
            onClicked: grid.quickSettings.networkHandler.enableWireless(!checked)
            onDetailsRequested: grid.quickSettings.page = "wifi"
        }
    }

    Component {
        id: bluetoothTile

        Tile {
            available: grid.quickSettings.hasBluetooth
            readonly property int connected: BluezQt.Manager.connectedDevices.length
            text: grid.tileName("bluetooth")
            iconName: checked ? "network-bluetooth" : "network-bluetooth-inactive"
            status: checked && connected > 0 ? i18ncp("@info:status", "%1 connected", "%1 connected", connected) : ""
            checked: BluezQt.Manager.bluetoothOperational
            hasDetails: true
            onClicked: grid.quickSettings.setBluetoothEnabled(!checked)
            onDetailsRequested: grid.quickSettings.page = "bluetooth"
        }
    }

    Component {
        id: airplaneTile

        Tile {
            available: grid.quickSettings.hasWifi
            text: grid.tileName("airplane-mode")
            iconName: "network-flightmode-on"
            checked: PlasmaNM.Configuration.airplaneModeEnabled
            onClicked: {
                const enable = !checked;
                grid.quickSettings.networkHandler.enableAirplaneMode(enable);
                PlasmaNM.Configuration.airplaneModeEnabled = enable;
            }
        }
    }

    Component {
        id: energySaverTile

        Tile {
            readonly property var profiles: grid.quickSettings.powerProfiles
            available: profiles.profiles.includes("power-saver")
            text: grid.tileName("energy-saver")
            iconName: "orielos-energy-saver-symbolic"
            checked: profiles.activeProfile === "power-saver"
            onClicked: profiles.setProfile(checked ? (profiles.configuredProfile && profiles.configuredProfile !== "power-saver" ? profiles.configuredProfile : "balanced") : "power-saver")
        }
    }

    Component {
        id: nightLightTile

        Tile {
            readonly property var nightLight: grid.quickSettings.nightLight
            available: nightLight.available
            text: grid.tileName("night-light")
            iconName: "orielos-night-light-symbolic"
            checked: nightLight.on
            status: {
                if (!checked || !nightLight.running || nightLight.nextChange <= 0) {
                    return "";
                }
                const time = new Date(nightLight.nextChange).toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
                return nightLight.daylight ? i18nc("@info:status %1 is a time", "From %1", time) : i18nc("@info:status %1 is a time", "Until %1", time);
            }
            onClicked: {
                if (!nightLight.enabled) {
                    grid.quickSettings.openSettings("night-light");
                } else {
                    Brightness.NightLightInhibitor.toggleInhibition();
                }
            }
        }
    }

    Component {
        id: accessibilityTile

        Tile {
            text: grid.tileName("accessibility")
            iconName: "orielos-accessibility-symbolic"
            onClicked: grid.quickSettings.openSettings("accessibility")
        }
    }

    Component {
        id: hotspotTile

        Tile {
            id: hotspot

            // The hotspot's connection path has no change signal; the handler says when it starts
            // or stops.
            function refresh() {
                checked = PlasmaNM.Configuration.hotspotConnectionPath !== "";
            }

            available: grid.quickSettings.networkHandler.hotspotSupported
            text: grid.tileName("mobile-hotspot")
            iconName: "network-wireless-hotspot"
            Component.onCompleted: refresh()
            onClicked: checked ? grid.quickSettings.networkHandler.stopHotspot() : grid.quickSettings.networkHandler.createHotspot()

            Connections {
                target: grid.quickSettings.networkHandler
                function onHotspotActiveChanged() {
                    hotspot.refresh();
                }
            }
        }
    }

    // Project opens Display mode (Win+P), through its global shortcut's launch action.
    Component {
        id: projectTile

        Tile {
            text: grid.tileName("project")
            iconName: "video-display"
            onClicked: {
                runner.connectSource("dbus-send --session --dest=org.kde.kglobalaccel --type=method_call /component/org_orielos_DisplayMode_desktop org.kde.kglobalaccel.Component.invokeShortcut string:_launch");
                grid.quickSettings.open = false;
            }
        }
    }

    // Keyboard layout steps to the next layout; it shows only with more than one.
    Component {
        id: keyboardTile

        Tile {
            available: keyboardLayout.layoutsList.length > 1
            text: grid.tileName("keyboard-layout")
            iconName: "input-keyboard"
            status: keyboardLayout.layoutsList[keyboardLayout.layout]?.longName ?? ""
            onClicked: keyboardLayout.switchToNextLayout()
        }
    }

    Keyboards.KeyboardLayout {
        id: keyboardLayout
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }
}
