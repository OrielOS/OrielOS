// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The first-run setup's updates page, as Windows checks for updates once it's connected: it looks
// for a newer OrielOS as soon as it shows and, if there is one, gets it ready to start the next
// time the computer restarts. It reads the same state as Settings' Update page (UpdateSettings).
// Next is never held up: setup can carry on while the check runs, or without a network.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import org.kde.plasmasetup.components as PlasmaSetupComponents
// The update model comes with OrielOS's first-run plugin, so that is loaded first.
import org.orielos.firstrun
import org.orielos.updatesettings

PlasmaSetupComponents.SetupModule {
    id: root

    // Plasma Setup's engine translates its own pages; this page's strings are in OrielOS's domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-first-run"
    }
    // Whether this page has started a check: it starts one the first time it shows.
    property bool started: false

    nextEnabled: true

    UpdateSettings {
        id: updates
    }

    contentItem: ColumnLayout {
        id: page

        onVisibleChanged: {
            if (visible && !root.started) {
                root.started = true;
                updates.checkForUpdates();
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignCenter
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                level: 2
                text: updates.checking || !root.started
                    ? root.l10n.i18nc("@title", "Checking for updates")
                    : (updates.updateWaiting ? root.l10n.i18nc("@title", "An update is ready") : root.l10n.i18nc("@title", "OrielOS is up to date"))
            }

            QQC2.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                visible: updates.checking || !root.started
                running: visible
            }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: {
                    if (updates.checking || !root.started) {
                        return root.l10n.i18nc("@info", "This can take a few minutes on a slow connection. You can carry on with the setup meanwhile.");
                    }
                    if (updates.updateWaiting) {
                        return root.l10n.i18nc("@info %1 is a version number", "OrielOS %1 starts the next time this computer restarts.", updates.stagedVersion);
                    }
                    return updates.detail;
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: updates.error.length > 0
                type: Kirigami.MessageType.Warning
                text: root.l10n.i18nc("@info %1 is why the check failed", "OrielOS couldn't check for updates: %1 It checks again by itself later.", updates.error)
            }
        }
    }
}
