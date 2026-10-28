// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Alt+F4 as in Windows: it closes the window in use, and with no window in use (the desktop, or
// nothing at all) it opens the Shut down dialog, which OrielOS's log-out screen draws when it's
// asked to shut down. KWin's own Close Window gives Alt+F4 up for this (the user's
// kglobalshortcutsrc, from /etc/skel or the orielos-close-shortcut user unit).

registerShortcut("Close Window or Shut Down", "Close the window, or offer to shut down on the desktop", "Alt+F4", function () {
    var window = workspace.activeWindow;
    if (window && !window.desktopWindow && !window.dock) {
        window.closeWindow();
        return;
    }
    callDBus("org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptShutDown");
});
