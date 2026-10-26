// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The first-run setup's power page: whether the computer sleeps when it isn't being used and
// after how long, and when the screen turns off. The choices become every new user's power
// settings. Plasma Setup tells a page nothing when Next or Back leaves it, but the page is hidden
// then, so that is when the choices are saved.

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

    PowerSettings {
        id: power
    }

    contentItem: ColumnLayout {
        id: page

        onVisibleChanged: {
            if (!visible) {
                power.save();
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
                text: root.l10n.i18nc("@info", "Choose when this computer saves power. You can change this later in Settings.")
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true

                QQC2.CheckBox {
                    Kirigami.FormData.label: root.l10n.i18nc("@label", "Sleep:")
                    text: root.l10n.i18nc("@option:check", "Put the computer to sleep when it isn't being used")
                    checked: power.sleepWhenIdle
                    onToggled: power.sleepWhenIdle = checked
                }

                QQC2.ComboBox {
                    Kirigami.FormData.label: root.l10n.i18nc("@label:listbox Sleep after a number of minutes", "After:")
                    enabled: power.sleepWhenIdle
                    model: power.sleepChoices
                    textRole: "text"
                    valueRole: "minutes"
                    currentIndex: indexOfValue(power.sleepAfterMinutes)
                    onActivated: power.sleepAfterMinutes = currentValue
                }

                QQC2.ComboBox {
                    Kirigami.FormData.label: root.l10n.i18nc("@label:listbox", "Turn off the screen after:")
                    model: power.screenOffChoices
                    textRole: "text"
                    valueRole: "minutes"
                    currentIndex: indexOfValue(power.screenOffAfterMinutes)
                    onActivated: power.screenOffAfterMinutes = currentValue
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: power.error.length > 0
                type: Kirigami.MessageType.Warning
                text: power.error
            }
        }
    }
}
