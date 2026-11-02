// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The Run this app window: what the file is and where it came from, then, once the user agrees,
// the program running, then what was added to Start.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import org.orielos.runapp

Kirigami.ApplicationWindow {
    id: root

    required property Runner runner

    readonly property bool confirming: runner.stage === Runner.Confirm
    readonly property bool running: runner.stage === Runner.Running
    readonly property bool finished: runner.stage === Runner.Finished

    title: KI18n.i18nc("@title:window", "Run this app")
    width: Kirigami.Units.gridUnit * 30
    height: Kirigami.Units.gridUnit * 20
    minimumWidth: Kirigami.Units.gridUnit * 24
    minimumHeight: Kirigami.Units.gridUnit * 16

    // Quitting would end the program too, so while it runs the window only goes out of the way.
    onClosing: close => {
        if (root.running) {
            close.accepted = false;
            root.showMinimized();
        }
    }

    pageStack.initialPage: Kirigami.Page {
        id: page

        title: root.runner.msi
            ? KI18n.i18nc("@title", "Install a Windows program")
            : KI18n.i18nc("@title", "Run a Windows program")

        Shortcut {
            sequences: [StandardKey.Cancel]
            enabled: !root.running
            onActivated: root.close()
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                    Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                    source: "application-x-ms-dos-executable"
                    fallback: "system-run"
                    Accessible.ignored: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        Layout.fillWidth: true
                        level: 2
                        wrapMode: Text.Wrap
                        text: {
                            if (root.confirming) {
                                return root.runner.msi
                                    ? KI18n.i18nc("@title", "Install this Windows program?")
                                    : KI18n.i18nc("@title", "Run this Windows program?");
                            }
                            if (root.running) {
                                return root.runner.msi
                                    ? KI18n.i18nc("@title %1 is a file name", "Installing %1…", root.runner.fileName)
                                    : KI18n.i18nc("@title %1 is a file name", "Running %1…", root.runner.fileName);
                            }
                            return root.runner.failed
                                ? KI18n.i18nc("@title", "Something went wrong")
                                : KI18n.i18nc("@title %1 is a program", "%1 has closed", root.runner.programName);
                        }
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        visible: root.confirming
                        text: root.runner.fileName
                        textFormat: Text.PlainText
                        font.bold: true
                        elide: Text.ElideMiddle
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        visible: root.confirming
                        wrapMode: Text.Wrap
                        text: root.runner.sourceHost.length > 0
                            ? KI18n.i18nc("@info %1 is a website", "From: %1", root.runner.sourceHost)
                            : KI18n.i18nc("@info", "Where this file came from isn't known.")

                        QQC2.ToolTip.visible: hoverHandler.hovered && root.runner.sourceUrl.length > 0
                        QQC2.ToolTip.text: root.runner.sourceUrl

                        HoverHandler {
                            id: hoverHandler
                        }
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        visible: root.confirming
                        text: KI18n.i18nc("@info %1 is a size such as 1.2 GB", "Size: %1", root.runner.size)
                    }
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.confirming && root.runner.appSource !== "store"
                type: Kirigami.MessageType.Warning
                text: KI18n.i18nc("@info", "Only run programs from people you trust. Windows programs can see your files.")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.confirming && root.runner.package
                type: Kirigami.MessageType.Error
                text: root.runner.knownName.length > 0
                    ? KI18n.i18nc("@info %1 is an app", "%1 installs as a Microsoft Store package, which OrielOS can't run.", root.runner.knownName)
                    : KI18n.i18nc("@info", "This is a Microsoft Store package, which OrielOS can't run.")
                actions: [
                    Kirigami.Action {
                        visible: root.runner.alternative.length > 0
                        text: KI18n.i18nc("@action:button", "Open the web version")
                        icon.name: "internet-web-browser"
                        onTriggered: {
                            Qt.openUrlExternally(root.runner.alternative);
                            root.close();
                        }
                    }
                ]
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.confirming && !root.runner.package && root.runner.storeApp.length > 0
                type: Kirigami.MessageType.Positive
                text: KI18n.i18nc("@info %1 is an app", "%1 is in the Store, ready for OrielOS, and updates by itself. It's better than the Windows version.", root.runner.knownName)
                actions: [
                    Kirigami.Action {
                        text: KI18n.i18nc("@action:button", "Get it from the Store")
                        icon.name: "plasmadiscover"
                        onTriggered: {
                            Qt.openUrlExternally("appstream://" + root.runner.storeApp);
                            root.close();
                        }
                    }
                ]
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.confirming && root.runner.launcherNote.length > 0
                type: Kirigami.MessageType.Information
                text: root.runner.launcherNote
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.confirming && root.runner.appSource === "suggest"
                type: Kirigami.MessageType.Information
                text: KI18n.i18nc("@info", "Look for this app in the Store first: apps from the Store are checked and update by themselves.")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.confirming && root.runner.appSource === "store"
                type: Kirigami.MessageType.Error
                text: KI18n.i18nc("@info", "This computer gets apps from the Store only. To run this program, change where apps can come from in Settings › Apps › Installed apps.")
                actions: [
                    Kirigami.Action {
                        text: KI18n.i18nc("@action:button", "Open Settings")
                        icon.name: "configure"
                        onTriggered: {
                            Qt.openUrlExternally("orielos-settings:installed-apps");
                            root.close();
                        }
                    }
                ]
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.running
                spacing: Kirigami.Units.largeSpacing

                QQC2.BusyIndicator {
                    running: root.running
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        Layout.fillWidth: true
                        visible: root.runner.firstDownload
                        wrapMode: Text.Wrap
                        text: KI18n.i18nc("@info", "Getting Windows compatibility ready. The first time takes a few minutes and downloads about 1 GB.")
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: KI18n.i18nc("@info", "Programs it installs are added to Start. You can minimise this window; it stays until the program closes.")
                    }
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.finished && root.runner.failed
                type: Kirigami.MessageType.Error
                text: root.runner.error
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                visible: root.runner.added.length > 0
                level: 4
                text: KI18n.i18nc("@title", "Added to Start")
            }

            Repeater {
                model: root.runner.added

                delegate: QQC2.Label {
                    required property string modelData

                    Layout.fillWidth: true
                    text: modelData
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: root.runner.canAddItself
                wrapMode: Text.Wrap
                text: KI18n.i18nc("@info %1 is a program", "Want to start %1 from Start next time?", root.runner.programName)
            }

            Item {
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Item {
                    Layout.fillWidth: true
                }

                QQC2.Button {
                    visible: root.finished && root.runner.failed
                    text: KI18n.i18nc("@action:button", "Open the Log")
                    icon.name: "text-x-log"
                    onClicked: root.runner.openLog()
                }

                QQC2.Button {
                    visible: root.runner.canAddItself
                    text: KI18n.i18nc("@action:button", "Add to Start")
                    icon.name: "list-add"
                    onClicked: root.runner.addItself()
                }

                QQC2.Button {
                    visible: !root.running
                    text: root.confirming ? KI18n.i18nc("@action:button", "Cancel") : KI18n.i18nc("@action:button", "Close")
                    icon.name: root.confirming ? "dialog-cancel" : "dialog-close"
                    onClicked: root.close()
                }

                QQC2.Button {
                    visible: root.confirming && root.runner.appSource !== "store" && !root.runner.package
                    text: root.runner.msi ? KI18n.i18nc("@action:button", "Install") : KI18n.i18nc("@action:button", "Run")
                    icon.name: "system-run"
                    onClicked: root.runner.run()
                }
            }
        }
    }
}
