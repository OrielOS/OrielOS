// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The mouse pointer's colour and size, as Windows' Accessibility › Mouse pointer offers them. Each
// change applies at once.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property PointerStyle pointer: PointerStyle {}
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
            visible: root.pointer.error.length > 0
            type: Kirigami.MessageType.Error
            text: root.pointer.error
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            enabled: !root.pointer.busy

            QQC2.ButtonGroup {
                id: colours
            }

            QQC2.RadioButton {
                Kirigami.FormData.label: root.l10n.i18nc("@title:group", "Mouse pointer style:")
                QQC2.ButtonGroup.group: colours
                text: root.l10n.i18nc("@option:radio A mouse pointer colour", "White")
                checked: root.pointer.white
                onToggled: {
                    if (checked) {
                        root.pointer.setWhite(true);
                    }
                    checked = Qt.binding(() => root.pointer.white);
                }
            }

            QQC2.RadioButton {
                QQC2.ButtonGroup.group: colours
                text: root.l10n.i18nc("@option:radio A mouse pointer colour", "Black")
                checked: !root.pointer.white
                onToggled: {
                    if (checked) {
                        root.pointer.setWhite(false);
                    }
                    checked = Qt.binding(() => !root.pointer.white);
                }
            }

            RowLayout {
                Kirigami.FormData.label: root.l10n.i18nc("@label:slider", "Size:")
                spacing: Kirigami.Units.largeSpacing

                QQC2.Slider {
                    id: size

                    Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                    from: root.pointer.minimumSize
                    to: root.pointer.maximumSize
                    stepSize: root.pointer.sizeStep
                    snapMode: QQC2.Slider.SnapAlways
                    value: root.pointer.size
                    Accessible.name: root.l10n.i18nc("@label:slider", "Size:")
                    // Applied when let go, not at every step of a drag.
                    onPressedChanged: {
                        if (!pressed) {
                            root.pointer.setSize(value);
                        }
                    }
                    Keys.onReleased: root.pointer.setSize(value)
                }

                QQC2.Label {
                    textFormat: Text.PlainText
                    text: root.l10n.i18nc("@info %1 is a size in pixels", "%1 px", Math.round(size.value))
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
                { page: "mouse", text: root.l10n.i18nc("@action:button A related Settings page", "Mouse") },
                { page: "accessibility", text: root.l10n.i18nc("@action:button A related Settings page", "Screen reader and keyboard") },
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
