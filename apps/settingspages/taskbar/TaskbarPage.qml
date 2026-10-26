// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The taskbar's alignment and whether it hides itself. Each change applies to the taskbar at once.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property TaskbarOptions options: TaskbarOptions {}
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
            text: root.l10n.i18nc("@info", "OrielOS's taskbar, the one with the Start menu, isn't on the desktop, so there's nothing to change here.")
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

            QQC2.ComboBox {
                Kirigami.FormData.label: root.l10n.i18nc("@label:listbox", "Taskbar alignment:")
                enabled: root.options.canAlign
                model: [root.l10n.i18nc("@item:inlistbox Taskbar alignment", "Centre"), root.l10n.i18nc("@item:inlistbox Taskbar alignment", "Left")]
                currentIndex: root.options.centred ? 0 : 1
                onActivated: index => {
                    root.options.centred = index === 0;
                    // Follow the setting again, which shows the old value if the change fails.
                    currentIndex = Qt.binding(() => root.options.centred ? 0 : 1);
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                visible: root.options.available && !root.options.canAlign
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                text: root.l10n.i18nc("@info", "The taskbar's widgets were rearranged, so its alignment can't be changed here.")
            }

            QQC2.Switch {
                Kirigami.FormData.label: root.l10n.i18nc("@title:group", "Behaviour:")
                text: root.l10n.i18nc("@option:check", "Automatically hide the taskbar")
                checked: root.options.autoHide
                onToggled: {
                    root.options.autoHide = checked;
                    checked = Qt.binding(() => root.options.autoHide);
                }
            }
        }
    }
}
