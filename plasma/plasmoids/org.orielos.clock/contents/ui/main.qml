// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The clock at the end of the taskbar, with the bell after it: the time over the date, and the
// bell with the number of new notifications, or with "zz" during Do not disturb. Either opens
// Sill's notification centre over the calendar. Plasma's notifications widget stays loaded among
// the hidden icons: it shows the pop-ups, and this one shows the same history.
//
// Sill draws the notifications and the calendar as two cards with a gap between them. Plasma's
// popups for taskbar widgets always draw one pane, so this widget has no popup of Plasma's: the
// clock and bell are its full representation, and it opens a window of its own with no pane, in
// which it draws the cards.

import QtQuick
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: root

    // The time, to the minute.
    property date now: new Date()
    readonly property bool showSeconds: Plasmoid.configuration.showSeconds
    onShowSecondsChanged: tick.restart()
    // Whether the notification centre is open.
    property bool open: false

    readonly property int unreadCount: Math.min(99, history.unreadNotificationsCount)
    readonly property bool doNotDisturb: {
        const until = settings.notificationsInhibitedUntil;
        const time = until ? until.getTime() : NaN;
        return (!isNaN(time) && root.now.getTime() < time) || settings.notificationsInhibitedByApplication;
    }

    // A focus session is Do not disturb until a set time; this is its end, in milliseconds since
    // the epoch, or 0 when none is running.
    readonly property double focusEnd: {
        const until = settings.notificationsInhibitedUntil;
        const time = until ? until.getTime() : NaN;
        return !isNaN(time) && time > root.now.getTime() ? time : 0;
    }
    // How long a focus session lasts, as last chosen.
    readonly property int focusMinutes: Plasmoid.configuration.focusMinutes

    // The lengths a focus session can be: 5 to 60 minutes in fives, then up to 4 hours in quarters.
    function nextFocusLength(minutes: int, step: int): int {
        if (step > 0) {
            return Math.min(240, minutes < 60 ? minutes + 5 : minutes + 15);
        }
        return Math.max(5, minutes <= 60 ? minutes - 5 : minutes - 15);
    }

    function setFocusMinutes(minutes: int) {
        Plasmoid.configuration.focusMinutes = minutes;
    }

    // While Do not disturb or a focus session is on, the taskbar's apps don't show badges or
    // progress, as in Windows' focus. Plasma's task manager has a setting for it; this changes it on
    // every task manager through the desktop's scripting, as a change in its settings would.
    function showTaskBadges(show: bool) {
        DBus.SessionBus.asyncCall({
            service: "org.kde.plasmashell",
            path: "/PlasmaShell",
            iface: "org.kde.PlasmaShell",
            member: "evaluateScript",
            arguments: ["panels().forEach(function (panel) { panel.widgets(\"org.kde.plasma.icontasks\").concat(panel.widgets(\"org.kde.plasma.taskmanager\")).forEach(function (tasks) {"
                + " tasks.currentConfigGroup = [\"General\"]; tasks.writeConfig(\"smartLaunchersEnabled\", " + show + "); tasks.reloadConfig(); }); });"],
        });
    }
    onDoNotDisturbChanged: showTaskBadges(!doNotDisturb)

    function setDoNotDisturb(minutes: int) {
        if (minutes > 0) {
            settings.notificationsInhibitedUntil = new Date(Date.now() + minutes * 60 * 1000);
        } else {
            settings.notificationsInhibitedUntil = undefined;
            settings.revokeApplicationInhibitions();
        }
        settings.save();
    }

    // The gap Sill leaves between the taskbar, or the screen's edge, and the cards.
    readonly property int gap: 12

    Plasmoid.icon: "preferences-system-time"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    toolTipMainText: Qt.locale().toString(root.now, "dddd d MMMM yyyy")
    toolTipSubText: root.unreadCount > 0 ? i18ncp("@info:tooltip", "%1 new notification", "%1 new notifications", root.unreadCount) : ""

    preferredRepresentation: fullRepresentation
    fullRepresentation: ClockButton {
        clock: root
    }

    // The notification centre's window: no pane of Plasma's, just the two cards, which keep the gap
    // from the taskbar and the screen's edge themselves.
    PlasmaCore.Dialog {
        id: centreWindow

        visualParent: root.fullRepresentationItem
        location: PlasmaCore.Types.BottomEdge
        type: PlasmaCore.Dialog.AppletPopup
        flags: Qt.WindowStaysOnTopHint
        backgroundHints: PlasmaCore.Dialog.NoBackground
        hideOnWindowDeactivate: true
        visible: root.open

        onVisibleChanged: {
            if (visible) {
                centreWindow.requestActivate();
            } else {
                root.open = false;
            }
        }

        mainItem: Centre {
            clock: root
            gap: root.gap
            focus: true
            Keys.onEscapePressed: root.open = false
        }
    }

    onOpenChanged: {
        if (root.open) {
            // Opening the centre reads everything in it.
            history.lastRead = undefined;
        }
    }

    Plasmoid.onActivated: root.open = !root.open

    // On the minute, or every second while the taskbar shows seconds.
    Timer {
        id: tick
        interval: 1000 * (60 - new Date().getSeconds())
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.now = new Date();
            interval = root.showSeconds ? 1000 - root.now.getMilliseconds() : 1000 * (60 - root.now.getSeconds());
        }
    }

    NotificationManager.Settings {
        id: settings
        live: true
    }

    // The history, newest first, as the notification centre lists it: an app's notifications under
    // its name, as Windows groups them, once it has more than one.
    NotificationManager.Notifications {
        id: history
        showExpired: true
        showDismissed: true
        showJobs: false
        sortMode: NotificationManager.Notifications.SortByDate
        groupMode: NotificationManager.Notifications.GroupApplicationsFlat
        blacklistedDesktopEntries: settings.historyBlacklistedApplications
        blacklistedNotifyRcNames: settings.historyBlacklistedServices
        urgencies: NotificationManager.Notifications.CriticalUrgency | NotificationManager.Notifications.NormalUrgency
            | (settings.lowPriorityHistory ? NotificationManager.Notifications.LowUrgency : 0)
    }

    readonly property alias history: history
    readonly property alias settings: settings
}
