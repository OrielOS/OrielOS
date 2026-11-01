// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.private.systemtray as SystemTray
import org.kde.plasma.workspace.dbus as DBus

// OrielOS's system tray, as Sill draws it: the hidden icons button, the apps' icons the user put on
// the taskbar, and the location icon while an app uses the location. The button opens the pane of
// hidden icons (HiddenIcons.qml); Win+B does too. Network, sound, battery and notifications are in
// Quick Settings and the clock, so only apps' icons show here. The widget hides itself when it has
// nothing to show.
PlasmoidItem {
    id: root

    readonly property string dragFormat: "application/x-orielos-tray-item"
    property bool paneOpen: false
    // While an icon is dragged out of the pane, the taskbar makes room for it after the arrow.
    property bool paneDragging: false

    // Bumped whenever an icon changes, so the bindings that read the model update.
    property int revision: 0
    // Each app's row in the model, by its id.
    property var rows: ({})
    property var taskbarIds: []
    property var paneIds: []

    readonly property var drives: Plasmoid.drives // qmllint disable missing-property
    readonly property int paneCount: root.paneIds.length + (root.drives.length > 0 ? 1 : 0)
    readonly property bool locationInUse: geoclue.item !== null && (geoclue.item as DBus.Properties).properties.InUse === true

    preferredRepresentation: fullRepresentation
    Plasmoid.status: {
        if (root.paneOpen) {
            return PlasmaCore.Types.RequiresAttentionStatus;
        }
        return root.taskbarIds.length > 0 || root.paneCount > 0 || root.locationInUse ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus;
    }

    function role(name: string): int {
        return items.KItemModels.KRoleNames.role(name);
    }

    function value(id: string, name: string): var {
        const row = root.rows[id];
        return row === undefined ? undefined : items.data(items.index(row, 0), root.role(name));
    }

    // Reads the apps' ids from the model and splits them between the taskbar and the pane. The
    // lists only change when their contents do, so the icons aren't made again on every update.
    function scan() {
        const rows = {};
        const present = [];
        const passive = [];
        const idRole = root.role("itemId");
        const statusRole = root.role("status");
        for (let row = 0; row < items.rowCount(); ++row) {
            const index = items.index(row, 0);
            const id = String(items.data(index, idRole) ?? "");
            if (id === "" || rows[id] !== undefined) {
                continue;
            }
            rows[id] = row;
            present.push(id);
            if (items.data(index, statusRole) === PlasmaCore.Types.PassiveStatus) {
                passive.push(id);
            }
        }
        root.rows = rows;
        // The pane lists the apps by name, so they keep their places from one session to the next.
        const titleRole = root.role("Title");
        const nameOf = id => String(items.data(items.index(rows[id], 0), titleRole) || id).toLowerCase();
        present.sort((a, b) => nameOf(a).localeCompare(nameOf(b)));
        const split = Plasmoid.split(present, passive, Plasmoid.configuration.shownItems); // qmllint disable missing-property
        if (JSON.stringify(split.taskbar) !== JSON.stringify(root.taskbarIds)) {
            root.taskbarIds = split.taskbar;
        }
        if (JSON.stringify(split.pane) !== JSON.stringify(root.paneIds)) {
            root.paneIds = split.pane;
        }
        root.revision++;
    }

    // The icon, title and tooltip text of an app's icon; `revision` makes the binding update.
    function iconOf(id: string, revision: int): var {
        if (root.value(id, "status") === PlasmaCore.Types.NeedsAttentionStatus) {
            const attention = root.value(id, "AttentionIcon") || root.value(id, "AttentionIconName");
            if (attention) {
                return attention;
            }
        }
        return root.value(id, "Icon") || root.value(id, "IconName") || "";
    }
    function titleOf(id: string, revision: int): string {
        return String(root.value(id, "ToolTipTitle") || root.value(id, "Title") || "");
    }
    function subTitleOf(id: string, revision: int): string {
        return String(root.value(id, "ToolTipSubTitle") || "");
    }

    function service(id: string): string {
        return String(root.value(id, "DataEngineSource") ?? "");
    }

    // qmllint disable missing-property
    function activateItem(id: string, item: Item) {
        if (root.value(id, "ItemIsMenu")) {
            Plasmoid.openMenu(root.service(id), item, item.width / 2, item.height / 2);
            return;
        }
        root.paneOpen = false;
        Plasmoid.activate(root.service(id), item);
    }
    function openItemMenu(id: string, item: Item, x: real, y: real) {
        Plasmoid.openMenu(root.service(id), item, x, y);
    }
    function middleClickItem(id: string, item: Item) {
        Plasmoid.secondaryActivate(root.service(id), item);
    }
    function scrollItem(id: string, delta: int, direction: string) {
        Plasmoid.scroll(root.service(id), delta, direction);
    }
    function showItem(id: string, index: int) {
        // The dragged icon leaves the pane before it can say its drag ended.
        root.paneDragging = false;
        Plasmoid.configuration.shownItems = Plasmoid.showAt(Plasmoid.configuration.shownItems, id, index);
    }
    function hideItem(id: string) {
        Plasmoid.configuration.shownItems = Plasmoid.hide(Plasmoid.configuration.shownItems, id);
    }
    function ejectDrive(udi: string) {
        root.paneOpen = false;
        Plasmoid.eject(udi);
    }
    // qmllint enable missing-property

    SystemTray.StatusNotifierModel {
        id: items
    }

    Connections {
        target: items
        function onRowsInserted() { root.scan(); }
        function onRowsRemoved() { root.scan(); }
        function onModelReset() { root.scan(); }
        function onDataChanged() { root.scan(); }
    }

    Connections {
        target: Plasmoid.configuration
        function onValueChanged() { root.scan(); }
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            if (root.paneCount > 0) {
                root.paneOpen = !root.paneOpen;
            }
        }
    }

    Component.onCompleted: root.scan()

    // GeoClue starts when an app asks for the location and stops when it's idle, each time under a
    // new D-Bus name, so its properties are read afresh whenever it starts.
    DBus.DBusServiceWatcher {
        id: geoclueService
        busType: DBus.BusType.System
        watchedService: "org.freedesktop.GeoClue2"
    }

    Loader {
        id: geoclue
        active: geoclueService.registered
        sourceComponent: DBus.Properties {
            busType: DBus.BusType.System
            service: "org.freedesktop.GeoClue2"
            path: "/org/freedesktop/GeoClue2/Manager"
            iface: "org.freedesktop.GeoClue2.Manager"
        }
    }

    fullRepresentation: Item {
        id: strip

        readonly property int iconWidth: 32

        Layout.minimumWidth: row.implicitWidth
        Layout.preferredWidth: row.implicitWidth
        Layout.maximumWidth: row.implicitWidth
        Layout.fillHeight: true

        RowLayout {
            id: row
            anchors.fill: parent
            spacing: 0

            ExpanderArrow {
                id: arrow
                Layout.fillHeight: true
                Layout.preferredWidth: 28
                visible: root.paneCount > 0
                open: root.paneOpen
                dragFormat: root.dragFormat
                onOpenRequested: open => root.paneOpen = open
            }

            Repeater {
                model: root.taskbarIds

                delegate: TrayIcon {
                    id: shown

                    required property string modelData
                    required property int index

                    Layout.fillHeight: true
                    Layout.preferredWidth: strip.iconWidth
                    radius: 6
                    location: Plasmoid.location
                    itemId: shown.modelData
                    dragFormat: root.dragFormat
                    source: root.iconOf(shown.modelData, root.revision)
                    title: root.titleOf(shown.modelData, root.revision)
                    subTitle: root.subTitleOf(shown.modelData, root.revision)
                    onActivated: root.activateItem(shown.modelData, shown)
                    onMenuRequested: (x, y) => root.openItemMenu(shown.modelData, shown, x, y)
                    onMiddleClicked: root.middleClickItem(shown.modelData, shown)
                    onScrolled: (delta, direction) => root.scrollItem(shown.modelData, delta, direction)
                }
            }

            // Where an icon dragged out of the pane can be dropped.
            Item {
                Layout.fillHeight: true
                Layout.preferredWidth: strip.iconWidth
                visible: root.paneDragging
            }

            TrayIcon {
                Layout.fillHeight: true
                Layout.preferredWidth: strip.iconWidth
                visible: root.locationInUse
                radius: 6
                location: Plasmoid.location
                source: "mark-location"
                title: KI18n.i18nc("@info:tooltip", "Location in use")
                subTitle: KI18n.i18nc("@info:tooltip", "An app is using this computer's location.")
                onActivated: Qt.openUrlExternally("orielos-settings:kcm_app-permissions")
                onMenuRequested: Qt.openUrlExternally("orielos-settings:kcm_app-permissions")
            }
        }

        // An app's icon dropped on the taskbar goes where it was dropped among the others. The arrow
        // keeps its own drop area, which opens the pane.
        DropArea {
            x: arrow.visible ? arrow.width : 0
            width: parent.width - x
            height: parent.height
            keys: [root.dragFormat]
            onDropped: drop => {
                root.showItem(drop.getDataAsString(root.dragFormat), Math.round(drop.x / strip.iconWidth));
                drop.accept(Qt.MoveAction);
            }
        }

        // The pane rises 12 px above the taskbar, like the other popups, over the button.
        PlasmaCore.AppletPopup {
            id: popup

            visualParent: arrow
            appletInterface: root
            popupDirection: {
                switch (Plasmoid.location) {
                case PlasmaCore.Types.TopEdge:
                    return Qt.BottomEdge;
                case PlasmaCore.Types.LeftEdge:
                    return Qt.RightEdge;
                case PlasmaCore.Types.RightEdge:
                    return Qt.LeftEdge;
                default:
                    return Qt.TopEdge;
                }
            }
            margin: 12
            floating: Plasmoid.location === PlasmaCore.Types.Floating
            removeBorderStrategy: PlasmaCore.AppletPopup.AtScreenEdges
            hideOnWindowDeactivate: true
            backgroundHints: PlasmaCore.AppletPopup.StandardBackground
            visible: root.paneOpen && root.paneCount > 0

            onVisibleChanged: {
                if (visible) {
                    popup.requestActivate();
                    pane.forceActiveFocus();
                } else {
                    paneSync.restart();
                }
            }

            mainItem: HiddenIcons {
                id: pane
                tray: root
                framePadding: popup.leftPadding
                ids: root.paneIds
                drives: root.drives
                Keys.onEscapePressed: root.paneOpen = false
            }
        }

        // The pane hides itself when another window is clicked; this keeps paneOpen in step.
        Timer {
            id: paneSync
            interval: 100
            onTriggered: root.paneOpen = popup.visible
        }
    }
}
