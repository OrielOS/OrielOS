// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// Alt+Tab as Windows shows it: the screen dims, and a pane in the middle holds the windows'
// thumbnails, most recently used first, each with its app's icon and title above it. The selected
// window is outlined in the highlight colour. Tab, Shift+Tab and the arrow keys move, the mouse
// picks, Delete closes the selected window and hovering a thumbnail shows an X to close it.

import QtQuick
import org.kde.kwin as KWin
import org.kde.plasma.core as PlasmaCore

KWin.TabBoxSwitcher {
    id: tabBox

    Instantiator {
        active: tabBox.visible

        delegate: PlasmaCore.Dialog {
            location: PlasmaCore.Types.Floating
            visible: true
            flags: Qt.Popup | Qt.X11BypassWindowManagerHint
            backgroundHints: PlasmaCore.Dialog.NoBackground
            x: tabBox.screenGeometry.x
            y: tabBox.screenGeometry.y

            mainItem: Thumbnails {
                width: tabBox.screenGeometry.width
                height: tabBox.screenGeometry.height
                switcher: tabBox
                focus: true
            }

            onSceneGraphError: () => {
                // Left empty on purpose: without it, Qt Quick can stop KWin after a graphics reset.
            }
        }
    }
}
