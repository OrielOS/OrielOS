// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.bluezqt as BluezQt
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.bluetooth as PlasmaBt

// Quick Settings' Bluetooth page: the paired devices, connected ones first, each with its battery
// when it reports one. Choosing one offers Connect or Disconnect; "Add device" opens Settings'
// Bluetooth page to pair a new one. Uses Plasma's Bluetooth services, as Plasma's own Bluetooth
// widget does.
SubPage {
    id: page

    readonly property bool bluetoothOn: BluezQt.Manager.bluetoothOperational

    title: i18nc("@title", "Bluetooth")
    hasSwitch: true
    switchChecked: page.bluetoothOn
    moreText: i18nc("@action:button", "More Bluetooth settings")
    morePage: "bluetooth"

    onToggled: page.quickSettings.setBluetoothEnabled(!page.bluetoothOn)

    footerItems: PC3.ToolButton {
        icon.name: "list-add"
        text: i18nc("@action:button Pair a new Bluetooth device", "Add device")
        font.pixelSize: 12
        onClicked: page.quickSettings.openSettings("bluetooth")
    }

    PlasmaBt.DevicesProxyModel {
        id: devices
        hideBlockedDevices: true
        sourceModel: PlasmaBt.SharedDevicesStateProxyModel
    }

    ListView {
        id: list

        anchors.fill: parent
        anchors.leftMargin: page.inset - 8
        anchors.rightMargin: page.inset - 8
        model: page.bluetoothOn ? devices : null
        currentIndex: -1
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: true
        PC3.ScrollBar.vertical: PC3.ScrollBar {}

        delegate: ListRow {
            id: device

            required property int index
            required property var model

            readonly property bool connected: device.model.Connected

            width: ListView.view.width
            text: device.model.DeviceFullName || device.model.Name
            iconName: device.model.Icon
            current: device.connected
            busy: device.model.Connecting || device.model.Disconnecting
            selected: ListView.isCurrentItem
            status: {
                if (device.model.Connecting) {
                    return i18nc("@info:status Bluetooth device", "Connecting");
                }
                if (device.model.Disconnecting) {
                    return i18nc("@info:status Bluetooth device", "Disconnecting");
                }
                const parts = [];
                if (device.model.ConnectionFailed) {
                    parts.push(i18nc("@info:status Bluetooth device", "Couldn't connect"));
                } else {
                    parts.push(device.connected ? i18nc("@info:status Bluetooth device", "Connected") : i18nc("@info:status Bluetooth device", "Paired"));
                }
                if (device.model.Battery) {
                    parts.push(i18nc("@info:status battery charge", "%1% battery", device.model.Battery.percentage));
                }
                return parts.join(" · ");
            }

            onClicked: list.currentIndex = device.selected ? -1 : device.index

            RowLayout {
                Layout.fillWidth: true

                Item {
                    Layout.fillWidth: true
                }

                PC3.Button {
                    text: device.connected ? i18nc("@action:button", "Disconnect") : i18nc("@action:button", "Connect")
                    enabled: !device.busy
                    onClicked: {
                        if (device.connected) {
                            PlasmaBt.SharedDevicesStateProxyModel.registerDisconnectingCallForDeviceUbi(device.model.Device.disconnectFromDevice(), device.model.Ubi);
                        } else {
                            PlasmaBt.SharedDevicesStateProxyModel.registerConnectingCallForDeviceUbi(device.model.Device.connectToDevice(), device.model.Ubi);
                        }
                        list.currentIndex = -1;
                    }
                }
            }
        }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - 2 * page.inset
            visible: list.count === 0
            iconName: page.bluetoothOn ? "network-bluetooth" : "network-bluetooth-inactive"
            text: page.bluetoothOn ? i18nc("@info:placeholder", "No paired devices") : i18nc("@info:placeholder", "Bluetooth is off")
        }
    }
}
