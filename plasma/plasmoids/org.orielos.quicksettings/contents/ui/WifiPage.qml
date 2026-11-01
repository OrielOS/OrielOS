// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.networkmanagement as PlasmaNM

// Quick Settings' Wi-Fi page: the networks in range, the one in use first, each with its signal
// and a lock when it's secured. Choosing one offers Connect or Disconnect, and a password box in
// place for a secured network that hasn't been used before. Uses Plasma's network services, as
// Plasma's own network widget does.
SubPage {
    id: page

    readonly property var handler: page.quickSettings.networkHandler
    readonly property bool wifiOn: page.quickSettings.enabledConnections.wirelessEnabled

    title: i18nc("@title", "Wi-Fi")
    hasSwitch: true
    switchChecked: page.wifiOn
    switchEnabled: !PlasmaNM.Configuration.airplaneModeEnabled && page.quickSettings.enabledConnections.wirelessHwEnabled
    moreText: i18nc("@action:button", "More Wi-Fi settings")
    morePage: "network"

    onToggled: page.handler.enableWireless(!page.wifiOn)
    Component.onCompleted: page.handler.requestScan()

    // Asks again every 15 seconds while the page is open, so new networks appear.
    Timer {
        interval: 15000
        repeat: true
        running: page.wifiOn
        onTriggered: page.handler.requestScan()
    }

    PlasmaNM.AppletProxyModel {
        id: sorted
        sourceModel: page.quickSettings.networkModel
    }

    KItemModels.KSortFilterProxyModel {
        id: networks
        sourceModel: sorted
        filterRoleName: "Type"
        filterRowCallback: (row, parent) => {
            const index = sorted.index(row, 0, parent);
            return sorted.data(index, sorted.KItemModels.KRoleNames.role("Type")) === PlasmaNM.Enums.Wireless;
        }
    }

    ListView {
        id: list

        anchors.fill: parent
        anchors.leftMargin: page.inset - 8
        anchors.rightMargin: page.inset - 8
        model: page.wifiOn ? networks : null
        currentIndex: -1
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: true
        PC3.ScrollBar.vertical: PC3.ScrollBar {}

        delegate: ListRow {
            id: network

            required property int index
            required property var model

            readonly property int connectionState: network.model.ConnectionState
            readonly property bool secured: network.model.SecurityType !== PlasmaNM.Enums.NoneSecurity
            readonly property bool staticPassword: [PlasmaNM.Enums.StaticWep, PlasmaNM.Enums.WpaPsk, PlasmaNM.Enums.Wpa2Psk, PlasmaNM.Enums.SAE]
                .includes(network.model.SecurityType)
            // A secured network with no saved connection asks for its password here.
            readonly property bool needsPassword: !network.model.Uuid && network.staticPassword

            width: ListView.view.width
            text: network.model.ItemUniqueName
            iconName: network.model.ConnectionIcon
            current: network.connectionState === PlasmaNM.Enums.Activated
            busy: network.connectionState === PlasmaNM.Enums.Activating || network.connectionState === PlasmaNM.Enums.Deactivating
            selected: ListView.isCurrentItem
            status: {
                if (network.busy) {
                    return network.model.DeviceState;
                }
                if (network.current) {
                    return network.secured ? i18nc("@info:status Wi-Fi network", "Connected, secured") : i18nc("@info:status Wi-Fi network", "Connected");
                }
                return network.secured ? i18nc("@info:status Wi-Fi network", "Secured") : i18nc("@info:status Wi-Fi network", "Open");
            }

            onClicked: list.currentIndex = network.selected ? -1 : network.index

            // Keeps the row from moving while the password is typed.
            onSelectedChanged: sorted.setData(networks.mapToSource(networks.index(network.index, 0)), network.selected && network.needsPassword,
                PlasmaNM.NetworkModel.DelayModelUpdatesRole)

            function connect() {
                if (network.needsPassword) {
                    if (!password.acceptableInput) {
                        password.forceActiveFocus();
                        return;
                    }
                    page.handler.addAndActivateConnection(network.model.DevicePath, network.model.SpecificPath, password.text);
                } else if (network.model.Uuid) {
                    page.handler.activateConnection(network.model.ConnectionPath, network.model.DevicePath, network.model.SpecificPath);
                } else {
                    page.handler.addAndActivateConnection(network.model.DevicePath, network.model.SpecificPath);
                }
                list.currentIndex = -1;
            }

            PlasmaExtras.PasswordField {
                id: password

                Layout.fillWidth: true
                visible: network.needsPassword && !network.current
                placeholderText: i18nc("@info:placeholder", "Enter the network security key")
                validator: RegularExpressionValidator {
                    regularExpression: network.model.SecurityType === PlasmaNM.Enums.StaticWep
                        ? /^(?:.{5}|[0-9a-fA-F]{10}|.{13}|[0-9a-fA-F]{26})$/
                        : /^(?:.{8,64})$/
                }
                onAccepted: network.connect()
                onVisibleChanged: {
                    if (visible) {
                        forceActiveFocus();
                    } else {
                        clear();
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }

                PC3.Button {
                    visible: network.needsPassword && !network.current
                    text: i18nc("@action:button", "Cancel")
                    onClicked: list.currentIndex = -1
                }

                PC3.Button {
                    text: network.current || network.busy ? i18nc("@action:button", "Disconnect") : i18nc("@action:button", "Connect")
                    enabled: network.current || network.busy || !network.needsPassword || password.acceptableInput
                    onClicked: {
                        if (network.current || network.busy) {
                            page.handler.deactivateConnection(network.model.ConnectionPath, network.model.DevicePath);
                            list.currentIndex = -1;
                        } else {
                            network.connect();
                        }
                    }
                }
            }
        }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - 2 * page.inset
            visible: list.count === 0
            iconName: PlasmaNM.Configuration.airplaneModeEnabled ? "network-flightmode-on" : (page.wifiOn ? "network-wireless-acquiring" : "network-wireless-off")
            text: {
                if (PlasmaNM.Configuration.airplaneModeEnabled) {
                    return i18nc("@info:placeholder", "Airplane mode is on");
                }
                return page.wifiOn ? i18nc("@info:placeholder", "Looking for networks") : i18nc("@info:placeholder", "Wi-Fi is off");
            }
        }
    }
}
