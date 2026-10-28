// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    Plasmoid.icon: Plasmoid.configuration.icon
    toolTipMainText: KI18n.i18nc("@info:tooltip The Start button's name", "Start")
    toolTipSubText: ""

    // The menu always opens as a popup, even when the widget is placed somewhere roomy.
    preferredRepresentation: compactRepresentation
    switchWidth: Kirigami.Units.gridUnit * 1000
    switchHeight: Kirigami.Units.gridUnit * 1000
    hideOnWindowDeactivate: true
    // The OrielOS shell opens the menu in the middle of the taskbar, like Sill's.
    readonly property bool centredPopup: true

    fullRepresentation: StartMenu {
        plasmoidItem: root
        focus: true
    }

    compactRepresentation: MouseArea {
        id: startButton

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        // Pressing the button while the menu is open closes it, so remember the state at the
        // press: by the time of the click the popup may already have closed on losing focus.
        property bool wasExpanded: false

        // A square button that fills the panel's thickness.
        Layout.minimumWidth: vertical ? 0 : height
        Layout.preferredWidth: vertical ? -1 : height
        Layout.minimumHeight: vertical ? width : 0
        Layout.preferredHeight: vertical ? width : -1

        hoverEnabled: true
        activeFocusOnTab: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        Accessible.name: Plasmoid.title
        Accessible.description: root.toolTipMainText
        Accessible.role: Accessible.Button

        onPressed: wasExpanded = root.expanded
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                // Windows' power user menu, as Win+X opens it.
                root.expanded = false;
                root.openPowerUserMenu();
                return;
            }
            root.expanded = !wasExpanded;
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.expanded = !root.expanded;
                event.accepted = true;
            }
        }

        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            active: startButton.containsMouse || startButton.pressed || root.expanded
        }
    }

    // Win+X (through the applet class) and a right-click on the button open it.
    function openPowerUserMenu() {
        powerUserMenu.open = !powerUserMenu.open;
    }

    PowerUserMenu {
        id: powerUserMenu
        visualParent: root.compactRepresentationItem
        onChosen: id => Plasmoid.activatePowerUserItem(id) // qmllint disable missing-property
    }

    Component.onCompleted: {
        // The Win key, which activates the launcher, toggles the menu like a click does.
        Plasmoid.activationTogglesExpanded = true;
    }
}
