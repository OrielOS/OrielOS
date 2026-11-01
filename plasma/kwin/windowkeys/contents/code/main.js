// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Windows' window shortcuts that KWin has no action for, or does differently:
//   Win+Up      maximises; a window snapped to a half goes to that half's top quarter
//   Win+Down    a snapped half goes to its bottom quarter; a maximised window is restored; any other
//               window is minimised
//   Win+M       minimises every window; Win+Shift+M brings them back
//   Win+Home    minimises every window but the one in use; again brings them back
//   Alt+Esc     sends the window in use to the back and switches to the next, with no switcher
//   Win+Ctrl+D  adds a desktop and switches to it; Win+Ctrl+F4 closes the one in use
//   Win+Alt+D   opens the clock's calendar, as Win+N does (a taskbar widget has only one shortcut)
// and, switching desktops, shows the desktop's name in the middle of the screen for a moment, and
// minimises the windows of a screen that is disconnected.
// KWin's own Maximise and Minimise give Win+Up and Win+Down up for this (the user's
// kglobalshortcutsrc, from /etc/skel or the orielos-user-shortcuts user unit).

function usable(window) {
    return window && window.normalWindow && !window.desktopWindow && !window.dock && !window.skipTaskbar;
}

function area(window) {
    return workspace.clientArea(KWin.MaximizeArea, window);
}

function near(a, b) {
    return Math.abs(a - b) <= 2;
}

// "left" or "right" for a window filling that half of its screen's work area, or "".
function snappedHalf(window) {
    var a = area(window);
    var g = window.frameGeometry;
    if (!near(g.y, a.y) || !near(g.height, a.height) || !near(g.width, a.width / 2)) {
        return "";
    }
    if (near(g.x, a.x)) {
        return "left";
    }
    return near(g.x + g.width, a.x + a.width) ? "right" : "";
}

function fillsArea(window) {
    var a = area(window);
    var g = window.frameGeometry;
    return near(g.x, a.x) && near(g.y, a.y) && near(g.width, a.width) && near(g.height, a.height);
}

// This desktop's windows that a shortcut may minimise, top first.
function desktopWindows() {
    var list = workspace.stackingOrder.filter(function (window) {
        return usable(window) && window.minimizable && (window.onAllDesktops || window.desktops.indexOf(workspace.currentDesktop) >= 0);
    });
    return list.reverse();
}

registerShortcut("OrielOS Maximise", "Maximise the window, or snap a half to its top quarter", "Meta+Up", function () {
    var window = workspace.activeWindow;
    if (!usable(window)) {
        return;
    }
    if (snappedHalf(window)) {
        // KWin puts a window tiled to one side and then to the top in that side's top quarter.
        workspace.slotWindowQuickTileTop();
    } else if (window.maximizable) {
        window.setMaximize(true, true);
    }
});

registerShortcut("OrielOS Restore or Minimise", "Restore a maximised window, minimise any other, or snap a half to its bottom quarter", "Meta+Down", function () {
    var window = workspace.activeWindow;
    if (!usable(window)) {
        return;
    }
    if (snappedHalf(window)) {
        workspace.slotWindowQuickTileBottom();
    } else if (fillsArea(window) && window.maximizable) {
        window.setMaximize(false, false);
    } else if (window.minimizable) {
        window.minimized = true;
    }
});

// The windows the last Win+M or Win+Home minimised, to bring back.
var minimisedByAll = [];
var minimisedByHome = [];

// Brings back windows minimised in this order (top first), leaving the top one in use.
function restore(windows) {
    windows.slice().reverse().forEach(function (window) {
        window.minimized = false;
    });
    if (windows.length > 0) {
        workspace.activeWindow = windows[0];
    }
}

registerShortcut("OrielOS Minimise All", "Minimise every window", "Meta+M", function () {
    minimisedByAll = desktopWindows().filter(function (window) {
        return !window.minimized;
    });
    minimisedByAll.forEach(function (window) {
        window.minimized = true;
    });
});

registerShortcut("OrielOS Restore All", "Bring back the windows Win+M minimised", "Meta+Shift+M", function () {
    restore(minimisedByAll);
    minimisedByAll = [];
});

registerShortcut("OrielOS Minimise Others", "Minimise every window but the one in use, or bring them back", "Meta+Home", function () {
    var active = workspace.activeWindow;
    if (minimisedByHome.length > 0) {
        restore(minimisedByHome);
        minimisedByHome = [];
        if (usable(active)) {
            workspace.activeWindow = active;
        }
        return;
    }
    if (!usable(active)) {
        return;
    }
    minimisedByHome = desktopWindows().filter(function (window) {
        return window !== active && !window.minimized;
    });
    minimisedByHome.forEach(function (window) {
        window.minimized = true;
    });
});

registerShortcut("OrielOS Send to Back", "Send the window to the back and switch to the next", "Alt+Esc", function () {
    var active = workspace.activeWindow;
    if (!usable(active)) {
        return;
    }
    workspace.slotWindowLower();
    var next = desktopWindows().filter(function (window) {
        return window !== active && !window.minimized;
    })[0];
    if (next) {
        workspace.activeWindow = next;
    }
});

registerShortcut("OrielOS New Desktop", "Add a desktop and switch to it", "Meta+Ctrl+D", function () {
    var count = workspace.desktops.length;
    workspace.createDesktop(count, "Desktop " + (count + 1));
    workspace.currentDesktop = workspace.desktops[count];
});

registerShortcut("OrielOS Close Desktop", "Close the desktop in use; its windows move to the one beside it", "Meta+Ctrl+F4", function () {
    if (workspace.desktops.length > 1) {
        // KWin moves the closed desktop's windows to the one before it.
        workspace.removeDesktop(workspace.currentDesktop);
    }
});

// Plasma's on-screen display shows the name, as Windows does when switching desktops.
workspace.currentDesktopChanged.connect(function () {
    if (workspace.desktops.length > 1) {
        callDBus("org.kde.plasmashell", "/org/kde/osdService", "org.kde.osdService", "showText", "virtual-desktops", workspace.currentDesktop.name);
    }
});

// The clock is a taskbar widget, with Win+N as its own shortcut; ask the desktop which widget it is,
// then invoke that widget's shortcut action.
registerShortcut("OrielOS Date and Time", "Open the clock's calendar and notifications", "Meta+Alt+D", function () {
    callDBus("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript",
        "var id = -1; panels().forEach(function (p) { p.widgets(\"org.orielos.clock\").forEach(function (w) { if (id < 0) { id = w.id; } }); }); print(id);",
        function (id) {
            if (String(id).trim() !== "-1") {
                callDBus("org.kde.kglobalaccel", "/component/plasmashell", "org.kde.kglobalaccel.Component", "invokeShortcut",
                    "activate widget " + String(id).trim());
            }
        });
});

// Peek at the desktop from the show desktop strip, when that's on in Taskbar settings: the strip
// invokes these, which have no keys, as the pointer rests on it and leaves.
registerShortcut("OrielOS Peek Start", "Show the desktop while the pointer rests on the show desktop strip", "", function () {
    workspace.showingDesktop = true;
});
registerShortcut("OrielOS Peek End", "Bring the windows back when the pointer leaves the show desktop strip", "", function () {
    workspace.showingDesktop = false;
});

// When a screen is disconnected, the windows that were on it are minimised rather than moved to
// another screen, as Windows offers (on unless Settings › System › Multitasking turns it off:
// [Script-orielos-windowkeys] MinimiseOnDisconnect in kwinrc). KWin moves the windows of a screen
// it removes, so a window whose last screen is no longer there was moved for that reason.
var lastScreen = {};

function rememberScreen(window) {
    if (usable(window) && window.output) {
        lastScreen[window.internalId] = window.output.name;
    }
}

function screenGone(name) {
    return !workspace.screens.some(function (screen) {
        return screen.name === name;
    });
}

function watchScreen(window) {
    rememberScreen(window);
    window.outputChanged.connect(function () {
        var before = lastScreen[window.internalId];
        if (before && screenGone(before) && usable(window) && window.minimizable && readConfig("MinimiseOnDisconnect", true)) {
            window.minimized = true;
        }
        rememberScreen(window);
    });
}

workspace.windowList().forEach(watchScreen);
workspace.windowAdded.connect(watchScreen);
workspace.windowRemoved.connect(function (window) {
    delete lastScreen[window.internalId];
});
