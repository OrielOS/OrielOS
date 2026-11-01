// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The taskbar's items (Search and Task View), its alignment, whether it hides itself, whether each
// app's windows share one button, and seconds in the clock. Each change applies to the taskbar at
// once.

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

    // Settings names the page above it, so the page's own title bar would only repeat the name.
    // System Settings has no such heading, so the title bar stays there.
    Component.onCompleted: {
        if (Qt.application.name === "orielos-settings") {
            globalToolBarStyle = Kirigami.ApplicationHeaderStyle.None;
        }
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

            QQC2.Switch {
                visible: root.options.hasSliver
                text: root.l10n.i18nc("@option:check", "Peek at the desktop when I point at the far corner of the taskbar")
                checked: root.options.peek
                onToggled: {
                    root.options.peek = checked;
                    checked = Qt.binding(() => root.options.peek);
                }
            }

            QQC2.Switch {
                text: root.l10n.i18nc("@option:check", "Use small taskbar buttons")
                checked: root.options.smallButtons
                onToggled: {
                    root.options.smallButtons = checked;
                    checked = Qt.binding(() => root.options.smallButtons);
                }
            }

            QQC2.Switch {
                text: root.l10n.i18nc("@option:check", "Show the taskbar on all displays")
                checked: root.options.allDisplays
                onToggled: {
                    root.options.allDisplays = checked;
                    checked = Qt.binding(() => root.options.allDisplays);
                }
            }

            QQC2.ComboBox {
                Kirigami.FormData.label: root.l10n.i18nc("@label:listbox", "Combine taskbar buttons:")
                enabled: root.options.hasTasks
                model: [root.l10n.i18nc("@item:inlistbox Combine taskbar buttons", "Always"), root.l10n.i18nc("@item:inlistbox Combine taskbar buttons", "Never")]
                currentIndex: root.options.combineButtons ? 0 : 1
                onActivated: index => {
                    root.options.combineButtons = index === 0;
                    currentIndex = Qt.binding(() => root.options.combineButtons ? 0 : 1);
                }
            }

            QQC2.Switch {
                Kirigami.FormData.label: root.l10n.i18nc("@title:group", "Taskbar items:")
                visible: root.options.hasSearch
                text: root.l10n.i18nc("@option:check", "Search")
                checked: root.options.showSearch
                onToggled: {
                    root.options.showSearch = checked;
                    checked = Qt.binding(() => root.options.showSearch);
                }
            }

            QQC2.Switch {
                visible: root.options.hasTaskView
                text: root.l10n.i18nc("@option:check", "Task View")
                checked: root.options.showTaskView
                onToggled: {
                    root.options.showTaskView = checked;
                    checked = Qt.binding(() => root.options.showTaskView);
                }
            }

            QQC2.Switch {
                Kirigami.FormData.label: root.l10n.i18nc("@title:group", "Clock:")
                visible: root.options.hasClock
                text: root.l10n.i18nc("@option:check", "Show seconds in the clock")
                checked: root.options.showSeconds
                onToggled: {
                    root.options.showSeconds = checked;
                    checked = Qt.binding(() => root.options.showSeconds);
                }
            }
        }

        // Related settings, as Windows lists them at the foot of a page.
        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.gridUnit
            level: 4
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@title:group", "Related settings")
        }

        Repeater {
            model: [
                { page: "start", text: root.l10n.i18nc("@action:button A related Settings page", "Start") },
                { page: "multitasking", text: root.l10n.i18nc("@action:button A related Settings page", "Multitasking") },
                { page: "notifications", text: root.l10n.i18nc("@action:button A related Settings page", "Notifications") },
            ]

            delegate: Kirigami.LinkButton {
                id: related

                required property var modelData

                text: related.modelData.text
                onClicked: Qt.openUrlExternally("orielos-settings:" + related.modelData.page)
            }
        }
    }
}
