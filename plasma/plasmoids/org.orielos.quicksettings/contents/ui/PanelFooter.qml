// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.coreaddons as KCoreAddons
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.battery as Battery

// Quick Settings' footer: the battery and its time left, then Edit and Settings.
PlasmaExtras.PlasmoidHeading {
    id: footer

    required property var quickSettings
    property int inset: 0

    readonly property var battery: footer.quickSettings.battery

    position: PC3.ToolBar.Footer
    leftPadding: footer.inset + 6
    rightPadding: footer.inset
    topPadding: Kirigami.Units.largeSpacing
    bottomPadding: Kirigami.Units.largeSpacing

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            visible: footer.quickSettings.hasBattery
            source: footer.quickSettings.batteryIcon
        }

        PC3.Label {
            Layout.fillWidth: true
            visible: footer.quickSettings.hasBattery
            textFormat: Text.PlainText
            font.pixelSize: 12
            elide: Text.ElideRight
            text: {
                const b = footer.battery;
                const percent = i18nc("@info:status battery charge", "%1%", b.percent);
                if (b.state === Battery.BatteryControlModel.Discharging && b.smoothedRemainingMsec > 0) {
                    const left = KCoreAddons.Format.formatDuration(b.smoothedRemainingMsec, KCoreAddons.FormatTypes.HideSeconds);
                    return i18nc("@info:status %1 is the charge, %2 the time left", "%1 · %2 left", percent, left);
                }
                if (b.state === Battery.BatteryControlModel.Charging) {
                    return i18nc("@info:status %1 is the charge", "%1 · Charging", percent);
                }
                return percent;
            }
        }

        Item {
            Layout.fillWidth: true
            visible: !footer.quickSettings.hasBattery
        }

        PC3.ToolButton {
            icon.name: "orielos-edit-symbolic"
            display: PC3.AbstractButton.IconOnly
            text: i18nc("@action:button Change which Quick Settings show", "Edit")
            Accessible.name: text
            PC3.ToolTip.text: text
            PC3.ToolTip.visible: hovered
            enabled: false
        }

        PC3.ToolButton {
            icon.name: "orielos-settings-symbolic"
            display: PC3.AbstractButton.IconOnly
            text: i18nc("@action:button", "Settings")
            Accessible.name: text
            PC3.ToolTip.text: text
            PC3.ToolTip.visible: hovered
            onClicked: footer.quickSettings.openSettings("")
        }
    }
}
