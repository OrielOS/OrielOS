// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Snap assist, as in Windows: when a window snaps to the left or right half of a screen (dragged to
// the edge, or Win+Left and Win+Right), the other half shows this desktop's other windows on that
// screen; clicking one snaps it into the other half beside the first. Escape, or a click anywhere
// else, leaves things as they are. It's a scene effect, so it has the keyboard and the mouse while
// it shows; each screen draws an Assist, and only the snapped window's screen offers windows.

import QtQuick
import org.kde.kwin

SceneEffect {
    id: effect

    // The window that was snapped, and the half it left free: "left" or "right". KWin Windows, as
    // QtObject properties, become null when the window goes.
    property QtObject snapped: null
    property string freeSide: ""
    // The windows offered, top of the stack first.
    property var candidates: []

    // "left" or "right" for a window filling that half of its screen's usable area, or "".
    function halfOf(window: QtObject): string {
        const area = Workspace.clientArea(Workspace.MaximizeArea, window);
        const g = window.frameGeometry;
        const near = (a, b) => Math.abs(a - b) <= 2;
        if (!near(g.y, area.y) || !near(g.height, area.height) || !near(g.width, area.width / 2)) {
            return "";
        }
        if (near(g.x, area.x)) {
            return "left";
        }
        return near(g.x + g.width, area.x + area.width) ? "right" : "";
    }

    function offerable(window: QtObject, beside: QtObject): bool {
        return window !== beside && window.normalWindow && !window.skipTaskbar && window.moveable && window.resizeable
            && !window.fullScreen && window.output === beside.output
            && (window.onAllDesktops || window.desktops.includes(Workspace.currentDesktop));
    }

    // After a window snaps: offer the others, unless the free half is already taken by a snapped
    // window or there's nothing to offer.
    function consider(window: QtObject) {
        if (effect.visible || !window || !window.tile) {
            return;
        }
        const side = effect.halfOf(window);
        if (side === "") {
            return;
        }
        const others = Workspace.stackingOrder.filter(other => effect.offerable(other, window)).reverse();
        const filled = others.some(other => !other.minimized && effect.halfOf(other) === (side === "left" ? "right" : "left"));
        if (others.length === 0 || filled) {
            return;
        }
        effect.snapped = window;
        effect.freeSide = side === "left" ? "right" : "left";
        effect.candidates = others;
        effect.visible = true;
    }

    function close() {
        effect.visible = false;
        effect.snapped = null;
        effect.candidates = [];
    }

    // Snap the chosen window into the free half, through KWin's own quick tiling, so the two are
    // tiled side by side as if both had been snapped by hand.
    function choose(window: QtObject) {
        const side = effect.freeSide;
        effect.close();
        if (!window) {
            return;
        }
        window.minimized = false;
        Workspace.activeWindow = window;
        if (side === "left") {
            Workspace.slotWindowQuickTileLeft();
        } else {
            Workspace.slotWindowQuickTileRight();
        }
    }

    onSnappedChanged: {
        if (effect.visible && !effect.snapped) {
            effect.close();
        }
    }

    // A window's tile changes as soon as it's snapped; its geometry follows a moment later.
    property QtObject pending: null
    Timer {
        id: settle
        interval: 250
        onTriggered: {
            effect.consider(effect.pending);
            effect.pending = null;
        }
    }

    function watch(window: QtObject) {
        window.tileChanged.connect(() => {
            if (window.tile) {
                effect.pending = window;
                settle.restart();
            }
        });
    }

    Component.onCompleted: {
        Workspace.stackingOrder.forEach(effect.watch);
        Workspace.windowAdded.connect(effect.watch);
    }

    delegate: Assist {}
}
