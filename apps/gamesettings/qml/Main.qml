// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// Game Settings: the games in Steam from the Store, and for each one its compatibility tool and
// switches (DLSS upgrade, HDR, gamescope, the FPS overlay, GameMode, DX12 descriptor heaps), which
// it writes into the game's launch options. Changes wait until Steam is closed.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.orielos.gamesettings

Kirigami.ApplicationWindow {
    id: root

    readonly property GameSettings settings: GameSettings {}
    property string pendingAddon: ""
    property string pendingGame: ""
    property string pendingOption: ""

    title: KI18n.i18nc("@title:window", "Game Settings")
    width: Kirigami.Units.gridUnit * 52
    height: Kirigami.Units.gridUnit * 36
    minimumWidth: Kirigami.Units.gridUnit * 30
    pageStack.initialPage: gamesPage
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.ToolBar

    function toggle(appId: string, name: string, on: bool): void {
        const addon = on ? root.settings.missingAddon(name) : "";
        if (addon.length > 0) {
            root.pendingAddon = addon;
            root.pendingGame = appId;
            root.pendingOption = name;
            addonDialog.open();
            return;
        }
        root.settings.setOption(appId, name, on);
    }

    Component {
        id: gamesPage

        Kirigami.ScrollablePage {
            title: KI18n.i18nc("@title", "Games")
            actions: [
                Kirigami.Action {
                    text: KI18n.i18nc("@action:button", "Will it run?")
                    icon.name: "help-about"
                    onTriggered: root.pageStack.push(willItRunPage)
                }
            ]

            header: ColumnLayout {
                spacing: 0

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    position: Kirigami.InlineMessage.Position.Header
                    visible: root.settings.steamRunning
                    type: Kirigami.MessageType.Information
                    text: KI18n.i18nc("@info", "Steam is open. Close it to change a game's settings: Steam saves its own settings as it closes.")
                    actions: [
                        Kirigami.Action {
                            text: KI18n.i18nc("@action:button", "Close Steam")
                            icon.name: "application-exit"
                            enabled: !root.settings.busy
                            onTriggered: root.settings.closeSteam()
                        }
                    ]
                }

                Kirigami.SearchField {
                    id: search

                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.largeSpacing
                    visible: root.settings.games.length > 0
                    placeholderText: KI18n.i18nc("@info:placeholder", "Search games")
                }
            }

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: root.settings.games.length === 0
                icon.name: "input-gaming"
                text: root.settings.steamInstalled ? KI18n.i18nc("@info", "No games installed yet") : KI18n.i18nc("@info", "Steam isn't installed")
                explanation: root.settings.steamInstalled
                    ? KI18n.i18nc("@info", "Install a game in Steam, and it shows here.")
                    : KI18n.i18nc("@info", "Install Steam from the Store; its games show here.")
                helpfulAction: Kirigami.Action {
                    enabled: !root.settings.steamInstalled
                    text: KI18n.i18nc("@action:button", "Get Steam")
                    icon.name: "plasmadiscover"
                    onTriggered: Qt.openUrlExternally("appstream://com.valvesoftware.Steam")
                }
            }

            GridView {
                id: grid

                readonly property int columns: Math.max(1, Math.floor(width / (Kirigami.Units.gridUnit * 9)))

                model: root.settings.games.filter(game => game.name.toLowerCase().includes(search.text.trim().toLowerCase()))
                cellWidth: width / columns
                cellHeight: cellWidth * 1.5 + Kirigami.Units.gridUnit * 2
                keyNavigationEnabled: true

                delegate: QQC2.ItemDelegate {
                    id: tile

                    required property var modelData

                    width: grid.cellWidth
                    height: grid.cellHeight
                    Accessible.name: tile.modelData.name
                    onClicked: root.pageStack.push(gamePage, { appId: tile.modelData.appId, gameName: tile.modelData.name })

                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Image {
                                anchors.fill: parent
                                source: tile.modelData.art.length > 0 ? "file://" + tile.modelData.art : ""
                                sourceSize.width: 300
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                            }

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: Kirigami.Units.iconSizes.huge
                                height: width
                                source: "input-gaming"
                                visible: tile.modelData.art.length === 0
                            }
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            text: tile.modelData.name
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }

    Component {
        id: gamePage

        Kirigami.ScrollablePage {
            id: page

            required property string appId
            required property string gameName
            // Read again after every change, which raises the revision.
            readonly property var current: root.settings.revision >= 0 ? root.settings.settingsFor(page.appId) : ({})
            readonly property bool locked: root.settings.steamRunning

            title: page.gameName

            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: page.locked
                    type: Kirigami.MessageType.Information
                    text: KI18n.i18nc("@info", "Close Steam to change these settings.")
                    actions: [
                        Kirigami.Action {
                            text: KI18n.i18nc("@action:button", "Close Steam")
                            icon.name: "application-exit"
                            onTriggered: root.settings.closeSteam()
                        }
                    ]
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: root.settings.error.length > 0
                    type: Kirigami.MessageType.Error
                    text: root.settings.error
                }

                Kirigami.FormLayout {
                    Layout.fillWidth: true
                    enabled: !page.locked && !root.settings.busy

                    QQC2.ComboBox {
                        Kirigami.FormData.label: KI18n.i18nc("@label:listbox", "Run Windows games with:")
                        model: root.settings.tools
                        textRole: "name"
                        valueRole: "id"
                        currentIndex: Math.max(0, indexOfValue(page.current.tool))
                        onActivated: root.settings.setTool(page.appId, currentValue)
                    }

                    Item {
                        Kirigami.FormData.isSection: true
                        Kirigami.FormData.label: KI18n.i18nc("@title:group", "Graphics")
                    }

                    QQC2.Switch {
                        text: KI18n.i18nc("@option:check", "Upgrade DLSS to the newest version")
                        checked: page.current.dlssUpgrade
                        onToggled: root.toggle(page.appId, "dlssUpgrade", checked)
                    }

                    QQC2.Switch {
                        text: KI18n.i18nc("@option:check", "HDR (Wine's Wayland driver)")
                        checked: page.current.waylandHdr
                        onToggled: root.toggle(page.appId, "waylandHdr", checked)
                    }

                    QQC2.Switch {
                        text: KI18n.i18nc("@option:check", "Run in gamescope, for scaling and frame limits")
                        checked: page.current.gamescope
                        onToggled: root.toggle(page.appId, "gamescope", checked)
                    }

                    QQC2.Switch {
                        text: KI18n.i18nc("@option:check", "DX12 descriptor heaps (faster on NVIDIA, may break some games)")
                        checked: page.current.descriptorHeap
                        onToggled: root.toggle(page.appId, "descriptorHeap", checked)
                    }

                    Item {
                        Kirigami.FormData.isSection: true
                        Kirigami.FormData.label: KI18n.i18nc("@title:group", "While playing")
                    }

                    QQC2.Switch {
                        text: KI18n.i18nc("@option:check", "FPS overlay (show it with Windows + G)")
                        checked: page.current.fpsOverlay
                        onToggled: root.toggle(page.appId, "fpsOverlay", checked)
                    }

                    QQC2.Switch {
                        text: KI18n.i18nc("@option:check", "GameMode")
                        checked: page.current.gameMode
                        onToggled: root.toggle(page.appId, "gameMode", checked)
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Kirigami.Theme.disabledTextColor
                    text: KI18n.i18nc("@info", "These go into the game's launch options in Steam, next to anything you typed there yourself. Turning one off takes out only what it added.")
                }
            }
        }
    }

    Component {
        id: willItRunPage

        Kirigami.ScrollablePage {
            id: willPage

            readonly property var results: root.settings.revision >= 0 ? root.settings.willItRun(question.text) : []

            title: KI18n.i18nc("@title", "Will it run?")

            header: Kirigami.SearchField {
                id: question

                focus: true
                placeholderText: KI18n.i18nc("@info:placeholder", "A game with anti-cheat, such as Fortnite")
            }

            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    visible: question.text.trim().length === 0
                    text: KI18n.i18nc("@info", "Search for a game with anti-cheat to see whether it runs on OrielOS. Most games without anti-cheat run.")
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    visible: question.text.trim().length > 0 && willPage.results.length === 0
                    text: KI18n.i18nc("@info", "Not in the list: if the game has no anti-cheat, it most likely runs.")
                }

                Repeater {
                    model: willPage.results

                    delegate: RowLayout {
                        id: answer

                        required property var modelData

                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing

                        Kirigami.Icon {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                            Layout.alignment: Qt.AlignTop
                            source: answer.modelData.status === "works" ? "data-success" : answer.modelData.status === "planned" ? "data-information" : "data-error"
                            Accessible.ignored: true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Kirigami.Heading {
                                Layout.fillWidth: true
                                level: 4
                                textFormat: Text.PlainText
                                text: answer.modelData.name
                            }

                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                text: answer.modelData.reason
                            }
                        }
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Kirigami.Theme.disabledTextColor
                    font: Kirigami.Theme.smallFont
                    text: KI18n.i18nc("@info %1 is a date", "From AreWeAntiCheatYet's list (MIT licence), as of %1, with OrielOS's own tests.", root.settings.willItRunDate)
                }
            }
        }
    }

    Kirigami.PromptDialog {
        id: addonDialog

        title: KI18n.i18nc("@title:dialog", "Install an add-on from the Store?")
        subtitle: root.pendingAddon === "gamescope"
            ? KI18n.i18nc("@info", "Steam from the Store needs its gamescope add-on to run games in gamescope.")
            : KI18n.i18nc("@info", "Steam from the Store needs the FPS overlay's add-on to show it in its games.")
        standardButtons: QQC2.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action {
                text: KI18n.i18nc("@action:button", "Install and turn on")
                icon.name: "download"
                onTriggered: {
                    root.settings.installAddon(root.pendingAddon);
                    root.settings.setOption(root.pendingGame, root.pendingOption, true);
                    addonDialog.close();
                }
            },
            Kirigami.Action {
                text: KI18n.i18nc("@action:button", "Cancel")
                icon.name: "dialog-cancel"
                onTriggered: addonDialog.close()
            }
        ]
    }
}
