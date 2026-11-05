// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// About: this PC's name, large, with its maker and model and Rename this PC, which opens a small
// editor on the page; then what's inside the PC and which OrielOS it runs, each with Copy; then a
// link to Plasma's page with every detail.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property AboutInfo info: AboutInfo {
        onRenamed: root.editing = false
    }
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }
    property bool editing: false
    // Why the name typed isn't usable, as it's typed.
    readonly property string problem: root.editing ? root.info.validate(nameField.text) : ""

    function startEditing() {
        nameField.text = root.info.name;
        root.editing = true;
        nameField.forceActiveFocus();
        nameField.selectAll();
    }

    function submit() {
        if (root.problem.length === 0 && !root.info.renaming && nameField.text !== root.info.name) {
            root.info.rename(nameField.text);
        }
    }

    // A card of label and value rows, with Copy, which says it copied for a moment.
    component SpecsCard: Kirigami.AbstractCard {
        id: card

        required property KI18nContext l10n
        required property string title
        required property var rows

        signal copyRequested

        Layout.fillWidth: true

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 4
                    textFormat: Text.PlainText
                    text: card.title
                }

                QQC2.Button {
                    id: copyButton

                    property bool copied: false

                    text: copied ? card.l10n.i18nc("@info The text is on the clipboard", "Copied") : card.l10n.i18nc("@action:button", "Copy")
                    icon.name: copied ? "checkmark" : "edit-copy"
                    Accessible.name: card.l10n.i18nc("@action:button %1 is a card's title", "Copy %1", card.title)
                    onClicked: {
                        card.copyRequested();
                        copied = true;
                        copiedTimer.restart();
                    }

                    Timer {
                        id: copiedTimer

                        interval: 2000
                        onTriggered: copyButton.copied = false
                    }
                }
            }

            Repeater {
                model: card.rows

                delegate: RowLayout {
                    id: specRow

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    QQC2.Label {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                        Layout.alignment: Qt.AlignTop
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        color: Kirigami.Theme.disabledTextColor
                        text: specRow.modelData.label
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: specRow.modelData.value
                    }
                }
            }
        }
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

        // The name, and the maker and model under it.
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                source: "computer"
                Accessible.ignored: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 1
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: root.info.name
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    color: Kirigami.Theme.disabledTextColor
                    text: root.info.device
                }
            }

            QQC2.Button {
                visible: !root.editing
                text: root.l10n.i18nc("@action:button", "Re&name this PC")
                icon.name: "edit-rename"
                onClicked: root.startEditing()
            }
        }

        // Renaming, on the page.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.editing
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.l10n.i18nc("@label:textbox", "New name for this PC:")
            }

            QQC2.TextField {
                id: nameField

                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 20
                enabled: !root.info.renaming
                Accessible.name: root.l10n.i18nc("@label:textbox", "New name for this PC")
                Accessible.description: root.problem.length > 0 ? root.problem : rule.text
                onAccepted: root.submit()
                Keys.onEscapePressed: root.editing = false
            }

            QQC2.Label {
                id: rule

                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Kirigami.Theme.disabledTextColor
                text: root.l10n.i18nc("@info", "Letters, numbers and hyphens, up to 63 characters")
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: root.problem.length > 0
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: Kirigami.Theme.negativeTextColor
                text: root.problem
            }

            RowLayout {
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: root.l10n.i18nc("@action:button", "&Rename")
                    icon.name: "dialog-ok-apply"
                    enabled: root.problem.length === 0 && !root.info.renaming && nameField.text !== root.info.name
                    onClicked: root.submit()
                }

                QQC2.Button {
                    text: root.l10n.i18nc("@action:button", "Cancel")
                    icon.name: "dialog-cancel"
                    enabled: !root.info.renaming
                    onClicked: root.editing = false
                }

                // Waiting for the administrator's password, then for the new name to be set.
                QQC2.BusyIndicator {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    visible: root.info.renaming
                    running: visible
                    Accessible.name: root.l10n.i18nc("@info", "Renaming this PC")
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: text.length > 0
            type: root.info.messageIsError ? Kirigami.MessageType.Error : Kirigami.MessageType.Positive
            text: root.info.message
        }

        SpecsCard {
            Layout.topMargin: Kirigami.Units.largeSpacing
            l10n: root.l10n
            title: root.l10n.i18nc("@title:group", "Device specifications")
            rows: root.info.deviceSpecs
            onCopyRequested: root.info.copyDevice()
        }

        SpecsCard {
            l10n: root.l10n
            title: root.l10n.i18nc("@title:group", "OrielOS specifications")
            rows: root.info.orielOSSpecs
            onCopyRequested: root.info.copyOrielOS()
        }

        Kirigami.LinkButton {
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: root.l10n.i18nc("@action:button A related Settings page", "All details")
            onClicked: Qt.openUrlExternally("orielos-settings:about-details")
        }
    }
}
