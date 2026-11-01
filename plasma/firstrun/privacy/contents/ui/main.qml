// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The first-run setup's privacy page, as Windows asks after the account, with the controls OrielOS
// actually has: location services, which apps use to find out where the computer is (GeoClue).
// OrielOS has no advertising ID or diagnostic data to switch off, and says so. The choice is saved
// when the page is left, as the power page does.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import org.kde.plasmasetup.components as PlasmaSetupComponents
import org.orielos.firstrun

PlasmaSetupComponents.SetupModule {
    id: root

    // Plasma Setup's engine translates its own pages; this page's strings are in OrielOS's domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-first-run"
    }

    nextEnabled: true

    PrivacySettings {
        id: privacy
    }

    contentItem: ColumnLayout {
        id: page

        onVisibleChanged: {
            if (!visible) {
                privacy.save();
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignCenter
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.largeSpacing

            QQC2.Label {
                Layout.fillWidth: true
                Layout.bottomMargin: Kirigami.Units.gridUnit
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.l10n.i18nc("@info", "Choose the privacy settings for this computer.")
            }

            QQC2.Switch {
                Layout.fillWidth: true
                text: root.l10n.i18nc("@option:check", "Location")
                checked: privacy.location
                onToggled: privacy.location = checked
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit * 2.5
                wrapMode: Text.Wrap
                opacity: 0.75
                text: root.l10n.i18nc("@info", "Let apps that ask, such as maps and weather, find out roughly where this computer is from nearby Wi-Fi networks. Off, no app can find out.")
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.gridUnit
                wrapMode: Text.Wrap
                text: root.l10n.i18nc("@info", "OrielOS doesn't collect diagnostic data or usage information, and it has no advertising ID.")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: privacy.error.length > 0
                type: Kirigami.MessageType.Warning
                text: privacy.error
            }
        }
    }
}
