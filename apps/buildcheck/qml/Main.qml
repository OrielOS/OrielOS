// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import org.orielos.buildcheck

Kirigami.ApplicationWindow {
    id: root

    title: KI18n.i18nc("@title:window", "OrielOS Build Check")
    width: Kirigami.Units.gridUnit * 24
    height: Kirigami.Units.gridUnit * 16

    pageStack.initialPage: Kirigami.Page {
        title: KI18n.i18nc("@title:page", "About This System")

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                text: KI18n.i18nc("@title product name", "OrielOS")
                Layout.alignment: Qt.AlignHCenter
            }

            QQC2.Label {
                text: SystemInfo.prettyName
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
