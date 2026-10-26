// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// What Start shows under Recommended. Each switch changes the Start menu on the taskbar at once.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property StartOptions options: StartOptions {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.options.ready && !root.options.available && root.options.error.length === 0
            type: Kirigami.MessageType.Information
            text: root.l10n.i18nc("@info", "OrielOS's Start menu isn't on the taskbar, so there's nothing to change here.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.options.error.length > 0
            type: Kirigami.MessageType.Error
            text: root.options.error
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            enabled: root.options.available

            QQC2.Switch {
                id: recentlyAdded

                Kirigami.FormData.label: root.l10n.i18nc("@title:group The Recommended section of Start", "Recommended:")
                text: root.l10n.i18nc("@option:check", "Show recently added apps")
                checked: root.options.showRecentlyAdded
                onToggled: {
                    root.options.showRecentlyAdded = checked;
                    // Follow the setting again, which shows the old value if the change fails.
                    checked = Qt.binding(() => root.options.showRecentlyAdded);
                }
            }

            QQC2.Switch {
                id: recentFiles

                text: root.l10n.i18nc("@option:check", "Show recently opened files")
                checked: root.options.showRecentFiles
                onToggled: {
                    root.options.showRecentFiles = checked;
                    checked = Qt.binding(() => root.options.showRecentFiles);
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                text: root.l10n.i18nc("@info", "Apps you installed in the last few days, and the files you opened most recently, show under Recommended in Start.")
            }
        }
    }
}
