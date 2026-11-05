// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The network troubleshooter's window: the seven checks as a path from the network adapter to the
// internet, each marked as it finishes. The first problem shows above them with Fix it when there's
// a fix; after a fix the checks run again by themselves.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.orielos.networktroubleshooter

QQC2.ApplicationWindow {
    id: root

    readonly property NetworkCheck network: NetworkCheck {}
    readonly property bool busy: root.network.running || root.network.fixing
    // What the checks found, once they've finished.
    readonly property string outcome: root.network.running ? "" : root.network.allPassed ? KI18n.i18nc("@info", "Your network connection is working.") : root.network.problem

    title: KI18n.i18nc("@title:window", "Network troubleshooter")
    width: Kirigami.Units.gridUnit * 28
    height: Kirigami.Units.gridUnit * 32
    minimumWidth: Kirigami.Units.gridUnit * 22
    minimumHeight: Kirigami.Units.gridUnit * 22
    color: Kirigami.Theme.backgroundColor

    // A screen reader hears the outcome when the checks finish.
    onOutcomeChanged: {
        if (root.outcome.length > 0) {
            content.Accessible.announce(root.outcome);
        }
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: root.close()
    }

    QQC2.ScrollView {
        id: scroll

        anchors.fill: parent
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        Item {
            implicitWidth: scroll.availableWidth
            implicitHeight: content.implicitHeight + Kirigami.Units.gridUnit * 2

            ColumnLayout {
                id: content

                anchors.fill: parent
                anchors.margins: Kirigami.Units.gridUnit
                spacing: Kirigami.Units.largeSpacing

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: KI18n.i18nc("@info",
                        "OrielOS checks each part of the connection in turn, from this PC's network adapter to the internet, and stops at the first problem.")
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: root.network.allPassed
                    type: Kirigami.MessageType.Positive
                    text: root.outcome
                }

                // The first problem, with its fix.
                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    type: Kirigami.MessageType.Warning
                    text: root.network.problem
                    actions: [
                        Kirigami.Action {
                            visible: root.network.problemFix.length > 0
                            enabled: !root.busy
                            icon.name: "tools-wizard"
                            text: root.network.fixing ? KI18n.i18nc("@action:button", "Fixing…") : KI18n.i18nc("@action:button", "Fix it")
                            onTriggered: root.network.fix(root.network.problemFix)
                        }
                    ]
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    type: Kirigami.MessageType.Information
                    text: root.network.notice
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    type: Kirigami.MessageType.Error
                    text: root.network.error
                }

                // The checks, joined by a thin line from the adapter down to the internet.
                ColumnLayout {
                    id: checkList

                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.largeSpacing

                    Repeater {
                        id: checkRows

                        model: root.network.checks

                        delegate: RowLayout {
                            id: row

                            required property var modelData
                            required property int index
                            readonly property string checkState: row.modelData.state
                            readonly property bool isLast: row.index === checkRows.count - 1

                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing

                            Accessible.role: Accessible.ListItem
                            Accessible.name: row.modelData.detail.length > 0
                                ? KI18n.i18nc("@info:accessibility %1 is a check, such as Router, %2 what it found", "%1: %2", row.modelData.title, row.modelData.detail)
                                : KI18n.i18nc("@info:accessibility %1 is a check, such as Router", "%1: not checked yet", row.modelData.title)

                            // The check's mark, and the line on to the next one.
                            Item {
                                id: mark

                                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                Layout.fillHeight: true
                                Accessible.ignored: true

                                Kirigami.Icon {
                                    width: Kirigami.Units.iconSizes.smallMedium
                                    height: Kirigami.Units.iconSizes.smallMedium
                                    visible: row.checkState === "ok" || row.checkState === "problem"
                                    source: row.checkState === "ok" ? "data-success" : "data-warning"
                                }

                                QQC2.BusyIndicator {
                                    id: spinner

                                    width: Kirigami.Units.iconSizes.smallMedium
                                    height: Kirigami.Units.iconSizes.smallMedium
                                    padding: 0
                                    visible: spinner.running
                                    running: row.checkState === "running"
                                }

                                // Not checked yet, or waiting for the problem above.
                                Rectangle {
                                    x: (Kirigami.Units.iconSizes.smallMedium - width) / 2
                                    y: x
                                    width: Kirigami.Units.iconSizes.smallMedium / 2
                                    height: width
                                    radius: width / 2
                                    visible: row.checkState === "pending" || row.checkState === "skipped"
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Kirigami.Theme.disabledTextColor
                                }

                                Rectangle {
                                    x: Math.round(Kirigami.Units.iconSizes.smallMedium / 2)
                                    y: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
                                    width: 1
                                    height: mark.height - y + checkList.spacing - Kirigami.Units.smallSpacing
                                    visible: !row.isLast
                                    color: Kirigami.Theme.disabledTextColor
                                    opacity: 0.5
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                QQC2.Label {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: row.checkState === "skipped" ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor
                                    text: row.modelData.title
                                }

                                QQC2.Label {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    wrapMode: Text.Wrap
                                    textFormat: Text.PlainText
                                    font: Kirigami.Theme.smallFont
                                    color: Kirigami.Theme.disabledTextColor
                                    text: row.modelData.detail
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.topMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Button {
                        text: KI18n.i18nc("@action:button", "&Check again")
                        icon.name: "view-refresh"
                        enabled: !root.busy
                        onClicked: root.network.run()
                    }

                    QQC2.Button {
                        text: KI18n.i18nc("@action:button", "&Network settings")
                        icon.name: "preferences-system-network"
                        onClicked: Qt.openUrlExternally("orielos-settings:network")
                    }
                }
            }
        }
    }
}
