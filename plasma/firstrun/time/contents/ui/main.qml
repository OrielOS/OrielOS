// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The first-run setup's time zone page, in place of Plasma Setup's own: the setup finds the time
// zone from the network (TimeZoneLookup) and sets it without asking. The page shows only while it
// can't tell, so offline, or before Wi-Fi is set up, it asks as Plasma Setup's page did. Once the
// page has shown, the zone chosen on it stands, even if the network answers later.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import org.kde.plasmasetup.components as PlasmaSetupComponents
import org.kde.plasmasetup.timeutil as Time
import org.kde.plasma.workspace.timezoneselector as TimeZone
import org.orielos.firstrun

PlasmaSetupComponents.SetupModule {
    id: root

    // Plasma Setup's engine translates its own pages; this page's strings are in OrielOS's domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-first-run"
    }
    // Whether the page has shown; from then on the choice is the user's.
    property bool shown: false

    available: root.shown || lookup.zone.length === 0
    nextEnabled: true

    TimeZoneLookup {
        id: lookup

        onZoneChanged: {
            if (!root.shown) {
                Time.TimeUtil.currentTimeZone = lookup.zone;
            }
        }
    }

    contentItem: ColumnLayout {
        id: page

        spacing: Kirigami.Units.largeSpacing

        onVisibleChanged: {
            if (visible) {
                root.shown = true;
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.l10n.i18nc("@info", "Choose your time zone. You can change it later in Settings.")
        }

        TimeZone.TimezoneSelector {
            id: selector

            Layout.fillWidth: true
            Layout.fillHeight: true
            // Set once made rather than bound: bound, the selector starts with an empty list.
            Component.onCompleted: selectedTimeZone = Time.TimeUtil.currentTimeZone
            onSelectedTimeZoneChanged: Time.TimeUtil.currentTimeZone = selectedTimeZone
        }
    }
}
