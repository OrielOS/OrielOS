// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Multitasking, as Windows' page offers it: snapping windows and its parts, and which windows
// Alt+Tab shows. Each switch applies at once.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property MultitaskingOptions options: MultitaskingOptions {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }

    // Settings names the page above it, so the page's own title bar would only repeat the name.
    // System Settings has no such heading, so the title bar stays there.
    Component.onCompleted: {
        if (Qt.application.name === "orielos-settings") {
            globalToolBarStyle = Kirigami.ApplicationHeaderStyle.None;
        }
    }

    Kirigami.FormLayout {
        QQC2.Switch {
            Kirigami.FormData.label: root.l10n.i18nc("@title:group", "Snap windows:")
            text: root.l10n.i18nc("@option:check", "Drag a window to an edge or corner of the screen to snap it there")
            checked: root.options.snapWindows
            onToggled: {
                root.options.snapWindows = checked;
                checked = Qt.binding(() => root.options.snapWindows);
            }
        }

        QQC2.Switch {
            text: root.l10n.i18nc("@option:check", "Show snap layouts when I rest the pointer on a window's maximise button")
            checked: root.options.snapLayoutsOnMaximise
            onToggled: {
                root.options.snapLayoutsOnMaximise = checked;
                checked = Qt.binding(() => root.options.snapLayoutsOnMaximise);
            }
        }

        QQC2.Switch {
            text: root.l10n.i18nc("@option:check", "When I snap a window, suggest what I can snap next to it")
            checked: root.options.suggestNextSnap
            onToggled: {
                root.options.suggestNextSnap = checked;
                checked = Qt.binding(() => root.options.suggestNextSnap);
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@info", "Windows + Z shows the snap layouts for the window in use, and Windows + the arrow keys snap it, whichever of these is on.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: root.l10n.i18nc("@label:listbox", "Alt + Tab shows the windows:")
            model: [
                root.l10n.i18nc("@item:inlistbox Alt+Tab shows the windows…", "On the desktop I'm using only"),
                root.l10n.i18nc("@item:inlistbox Alt+Tab shows the windows…", "On all desktops"),
            ]
            currentIndex: root.options.altTabAllDesktops ? 1 : 0
            onActivated: index => {
                root.options.altTabAllDesktops = index === 1;
                currentIndex = Qt.binding(() => root.options.altTabAllDesktops ? 1 : 0);
            }
        }
    }
}
