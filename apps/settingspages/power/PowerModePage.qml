// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The power mode: Performance, Balanced or Power saver, the same choice as in the tray's power and
// battery widget. OrielOS starts in Performance; a mode chosen here is kept.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property PowerMode power: PowerMode {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.power.ready && !root.power.available
            type: Kirigami.MessageType.Warning
            text: root.l10n.i18nc("@info", "The power profiles service isn't running, so the power mode can't be changed.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.power.error.length > 0
            type: Kirigami.MessageType.Error
            text: root.power.error
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.power.degraded.length > 0
            type: Kirigami.MessageType.Information
            text: root.power.degraded
        }

        QQC2.ButtonGroup {
            id: group
        }

        Repeater {
            model: root.power.modes

            delegate: ColumnLayout {
                id: mode

                required property var modelData

                Layout.fillWidth: true
                spacing: 0

                QQC2.RadioButton {
                    QQC2.ButtonGroup.group: group
                    text: mode.modelData.name
                    checked: root.power.active === mode.modelData.id
                    Accessible.description: mode.modelData.description
                    onToggled: {
                        if (checked) {
                            root.power.active = mode.modelData.id;
                        }
                        // Follow the daemon again, which shows the old mode if the change fails.
                        checked = Qt.binding(() => root.power.active === mode.modelData.id);
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit * 2
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    textFormat: Text.PlainText
                    text: mode.modelData.description
                }
            }
        }
    }
}
