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

        Accessible.name: Plasmoid.title
        Accessible.description: root.toolTipMainText
        Accessible.role: Accessible.Button

        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded
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

    Component.onCompleted: {
        // The Win key, which activates the launcher, toggles the menu like a click does.
        Plasmoid.activationTogglesExpanded = true;
    }
}
