// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The taskbar's Task View button, after Search: shows every open window and the desktops, as
// Win+Tab does (KWin's Overview). Sill: a 44 px button with two overlapping windows and a rounded
// highlight when hovered or pressed, then a short line that sets the apps apart. Keep this in step
// with org.orielos.search, its twin. Resting on the button shows the desktops, as Windows does, to
// switch to one or add one.

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    readonly property string command: "dbus-send --session --dest=org.kde.kglobalaccel --type=method_call /component/kwin org.kde.kglobalaccel.Component.invokeShortcut string:Overview"

    preferredRepresentation: fullRepresentation
    toolTipMainText: Plasmoid.title
    toolTipSubText: ""

    // Whether the pointer is over the button or the desktops it shows.
    property bool overButton: false
    property bool overDesktops: false

    TaskManager.VirtualDesktopInfo {
        id: desktops
    }

    // The desktops show after a short rest on the button and go a moment after the pointer leaves.
    Timer {
        id: showDesktops
        interval: 500
        onTriggered: desktopsWindow.visible = true
    }
    Timer {
        id: hideDesktops
        interval: 400
        onTriggered: desktopsWindow.visible = false
    }
    onOverButtonChanged: root.followPointer()
    onOverDesktopsChanged: root.followPointer()

    function followPointer() {
        if (root.overButton || root.overDesktops) {
            hideDesktops.stop();
            if (!desktopsWindow.visible && root.overButton) {
                showDesktops.restart();
            }
        } else {
            showDesktops.stop();
            hideDesktops.restart();
        }
    }

    // KWin adds a desktop at the end, named as Windows names them.
    function newDesktop() {
        const name = i18nc("@item A virtual desktop's name, %1 is its number", "Desktop %1", desktops.numberOfDesktops + 1).replace(/'/g, "");
        runner.connectSource("dbus-send --session --type=method_call --dest=org.kde.KWin /VirtualDesktopManager "
            + "org.kde.KWin.VirtualDesktopManager.createDesktop uint32:" + desktops.numberOfDesktops + " 'string:" + name + "'");
    }

    PlasmaCore.Dialog {
        id: desktopsWindow

        visualParent: root.fullRepresentationItem
        location: PlasmaCore.Types.BottomEdge
        type: PlasmaCore.Dialog.Tooltip
        flags: Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus

        mainItem: MouseArea {
            implicitWidth: strip.implicitWidth + Kirigami.Units.largeSpacing * 2
            implicitHeight: strip.implicitHeight + Kirigami.Units.largeSpacing * 2
            hoverEnabled: true
            onContainsMouseChanged: root.overDesktops = containsMouse

            Row {
                id: strip

                anchors.centerIn: parent
                spacing: Kirigami.Units.largeSpacing

                Repeater {
                    model: desktops.numberOfDesktops

                    delegate: PC3.ToolButton {
                        id: desktop

                        required property int index
                        readonly property bool current: desktops.desktopIds[desktop.index] === desktops.currentDesktop

                        width: 140
                        height: 84
                        checkable: true
                        checked: desktop.current
                        text: desktops.desktopNames[desktop.index] ?? ""
                        Accessible.name: text
                        onClicked: {
                            desktops.requestActivate(desktops.desktopIds[desktop.index]);
                            desktopsWindow.visible = false;
                        }

                        contentItem: PC3.Label {
                            text: desktop.text
                            textFormat: Text.PlainText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignBottom
                            elide: Text.ElideRight
                        }
                        background: Rectangle {
                            radius: 6
                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, desktop.hovered ? 0.12 : 0.06)
                            border.width: desktop.current ? 2 : 1
                            border.color: desktop.current ? Kirigami.Theme.highlightColor
                                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                        }
                    }
                }

                PC3.ToolButton {
                    width: 140
                    height: 84
                    icon.name: "list-add"
                    text: i18nc("@action:button Add a virtual desktop", "New desktop")
                    display: PC3.AbstractButton.TextUnderIcon
                    onClicked: root.newDesktop()
                }
            }
        }
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    fullRepresentation: MouseArea {
        id: button

        // The button, then the line in the middle of a 13 px gap.
        readonly property int dividerSpace: 13

        // Settings › Personalisation › Taskbar can hide the button; it then takes no room.
        visible: Plasmoid.configuration.shown
        implicitWidth: visible ? 44 + dividerSpace : 0
        implicitHeight: 40
        Layout.minimumWidth: visible ? 44 + dividerSpace : 0
        Layout.maximumWidth: visible ? 44 + dividerSpace : 0
        Layout.minimumHeight: 40
        Layout.fillHeight: true
        Layout.preferredWidth: visible ? 44 + dividerSpace : 0
        hoverEnabled: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: Plasmoid.title

        onClicked: {
            desktopsWindow.visible = false;
            runner.connectSource(root.command);
        }
        onContainsMouseChanged: root.overButton = containsMouse
        Keys.onReturnPressed: runner.connectSource(root.command)
        Keys.onSpacePressed: runner.connectSource(root.command)

        Rectangle {
            id: highlight
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 40
            radius: 6
            color: Kirigami.Theme.textColor
            opacity: button.pressed ? 0.14 : (button.containsMouse || button.activeFocus ? 0.08 : 0)
        }

        Kirigami.Icon {
            anchors.centerIn: highlight
            width: Kirigami.Units.iconSizes.smallMedium
            height: Kirigami.Units.iconSizes.smallMedium
            source: "window-duplicate"
        }

        Rectangle {
            x: 44 + (button.dividerSpace - 1) / 2
            width: 1
            height: 24
            anchors.verticalCenter: parent.verticalCenter
            color: Kirigami.Theme.textColor
            opacity: 0.16
        }
    }
}
