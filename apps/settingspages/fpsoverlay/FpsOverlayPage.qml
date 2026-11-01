// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Settings › Gaming › FPS overlay: OrielOS's Game Bar, a frame-rate overlay over games that Windows
// + G shows or hides. Each change applies at once.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property FpsOverlay overlay: FpsOverlay {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.overlay.error.length > 0
            type: Kirigami.MessageType.Error
            text: root.overlay.error
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.Switch {
                Kirigami.FormData.label: root.l10n.i18nc("@label:checkbox", "FPS overlay:")
                text: root.overlay.enabled ? root.l10n.i18nc("@option:check", "On") : root.l10n.i18nc("@option:check", "Off")
                checked: root.overlay.enabled
                enabled: !root.overlay.busy
                onToggled: {
                    root.overlay.setEnabled(checked);
                    checked = Qt.binding(() => root.overlay.enabled);
                }
            }

            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                text: root.l10n.i18nc("@info", "Press Windows + G in a game to show or hide the frame rate in its top-left corner. Games you start after you next sign in have it; it stays hidden until you press the keys.")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.Wrap
            }

            QQC2.CheckBox {
                Kirigami.FormData.label: root.l10n.i18nc("@label", "Also show:")
                text: root.l10n.i18nc("@option:check", "Frame time")
                checked: root.overlay.frameTime
                enabled: root.overlay.enabled && !root.overlay.busy
                onToggled: {
                    root.overlay.setFrameTime(checked);
                    checked = Qt.binding(() => root.overlay.frameTime);
                }
            }

            QQC2.CheckBox {
                text: root.l10n.i18nc("@option:check", "Processor and graphics card use")
                checked: root.overlay.stats
                enabled: root.overlay.enabled && !root.overlay.busy
                onToggled: {
                    root.overlay.setStats(checked);
                    checked = Qt.binding(() => root.overlay.stats);
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.overlay.enabled && root.overlay.steamNeedsAddon
            type: Kirigami.MessageType.Information
            text: root.l10n.i18nc("@info", "Steam from the Store needs the overlay's add-on, from the Store, to show it in its games.")
            actions: [
                Kirigami.Action {
                    text: root.l10n.i18nc("@action:button", "Install the add-on")
                    icon.name: "download"
                    enabled: !root.overlay.busy
                    onTriggered: root.overlay.installSteamAddon()
                }
            ]
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: root.l10n.i18nc("@info", "A few games with anti-cheat may refuse to start with an overlay; turn it off for those.")
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
        }
    }
}
