// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The first-run setup's network page for a computer without Wi-Fi. Plasma Setup's own network page
// lists Wi-Fi networks and only appears when there is a wireless device; this one takes its place
// otherwise and shows whether the cable connection reaches the internet.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.plasmasetup.components as PlasmaSetupComponents

PlasmaSetupComponents.SetupModule {
    id: root

    // NetworkManager's connectivity values (NetworkManager::Connectivity).
    readonly property int portal: 2
    readonly property int limited: 3
    readonly property int full: 4

    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-first-run"
    }

    available: !devices.wirelessDeviceAvailable

    PlasmaNM.AvailableDevices {
        id: devices
    }

    PlasmaNM.NetworkStatus {
        id: status
    }

    contentItem: ColumnLayout {
        ColumnLayout {
            Layout.alignment: Qt.AlignCenter
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                source: status.connectivity === root.full ? "network-wired-activated" : "network-wired-disconnected"
                Accessible.ignored: true
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 3
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: {
                    if (status.connectivity === root.full) {
                        return root.l10n.i18nc("@info", "This computer is connected to the internet by cable.");
                    }
                    if (status.connectivity === root.portal || status.connectivity === root.limited) {
                        return root.l10n.i18nc("@info", "This computer is connected to a network, but it doesn't reach the internet yet.");
                    }
                    return root.l10n.i18nc("@info", "This computer isn't connected to a network.");
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: status.connectivity !== root.full
                text: root.l10n.i18nc("@info", "Plug in a network cable, or carry on and connect later from the network icon on the taskbar.")
            }
        }
    }
}
