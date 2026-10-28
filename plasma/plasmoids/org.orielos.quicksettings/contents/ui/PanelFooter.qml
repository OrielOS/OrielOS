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
    // The tile grid, whose unpinned tiles Add offers while editing.
    property var tiles: null

    readonly property var battery: footer.quickSettings.battery

    position: PC3.ToolBar.Footer
    leftPadding: footer.inset
    rightPadding: footer.inset - 8
    topPadding: Kirigami.Units.largeSpacing
    bottomPadding: Kirigami.Units.largeSpacing

    // Sill's footer: a darker band under a hairline, rounded at the bottom like its card.
    background: Item {
        implicitHeight: 52

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.18)
        }
        // Squares off the band's top corners.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 8
            color: Qt.rgba(0, 0, 0, 0.18)
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Kirigami.Theme.textColor
            opacity: 0.08
        }
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            visible: footer.quickSettings.hasBattery && !footer.quickSettings.editing
            source: footer.quickSettings.batteryIcon
        }

        PC3.Label {
            Layout.fillWidth: true
            visible: footer.quickSettings.hasBattery && !footer.quickSettings.editing
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

        // While editing: Add, a menu of the unpinned tiles, then Done.
        PC3.ToolButton {
            id: addButton

            visible: footer.quickSettings.editing
            enabled: (footer.tiles?.unpinned.length ?? 0) > 0
            icon.name: "list-add"
            text: i18nc("@action:button Add a tile to Quick Settings", "Add")
            font.pixelSize: 12
            onClicked: addMenu.popup(addButton, 0, -addMenu.implicitHeight)
        }

        PC3.Menu {
            id: addMenu

            Instantiator {
                model: footer.tiles?.unpinned ?? []
                delegate: PC3.MenuItem {
                    required property string modelData
                    text: footer.tiles.tileName(modelData)
                    onTriggered: footer.tiles.pin(modelData)
                }
                onObjectAdded: (index, object) => addMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => addMenu.removeItem(object)
            }
        }

        Item {
            Layout.fillWidth: true
            visible: !footer.quickSettings.hasBattery || footer.quickSettings.editing
        }

        PC3.Button {
            visible: footer.quickSettings.editing
            text: i18nc("@action:button Finish editing Quick Settings", "Done")
            font.pixelSize: 12
            onClicked: footer.quickSettings.editing = false
        }

        PC3.ToolButton {
            visible: !footer.quickSettings.editing
            icon.name: "orielos-edit-symbolic"
            display: PC3.AbstractButton.IconOnly
            text: i18nc("@action:button Change which Quick Settings show", "Edit")
            Accessible.name: text
            PC3.ToolTip.text: text
            PC3.ToolTip.visible: hovered
            onClicked: footer.quickSettings.editing = true
        }

        PC3.ToolButton {
            visible: !footer.quickSettings.editing
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
