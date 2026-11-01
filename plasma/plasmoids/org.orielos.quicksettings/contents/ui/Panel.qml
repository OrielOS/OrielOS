// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.volume as Volume

// Sill's Quick Settings: what's playing on a card of its own, then the card with the tiles, the
// brightness and volume sliders, and the footer with the battery, 12 px apart, with the same gap to
// the taskbar under them and to the screen's edge beside them, left clear.
Item {
    id: panel

    required property var quickSettings

    readonly property int inset: 20
    readonly property int gap: panel.quickSettings.gap
    readonly property var player: panel.quickSettings.media.currentPlayer

    width: cards.width + panel.gap
    height: cards.implicitHeight + panel.gap

    ColumnLayout {
        id: cards

        width: 3 * 107 + 2 * 10 + 2 * panel.inset
        spacing: panel.gap

        MediaCard {
            Layout.fillWidth: true
            visible: panel.player !== null && (panel.player?.track ?? "").length > 0
            player: panel.player
        }

        Card {
            Layout.fillWidth: true
            // A sub-page takes the settings' place at the same height, or a little more for a short
            // list of tiles, and scrolls what doesn't fit.
            implicitHeight: panel.quickSettings.page === "" ? settings.implicitHeight : Math.max(settings.implicitHeight, 380)

            ColumnLayout {
                id: settings

                anchors.left: parent.left
                anchors.right: parent.right
                visible: panel.quickSettings.page === ""
                spacing: 0

                TileGrid {
                    id: tileGrid

                    Layout.fillWidth: true
                    Layout.margins: panel.inset
                    quickSettings: panel.quickSettings
                }

                // The pages of tiles, as dots like Start's; a click turns to that page.
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 4
                    visible: tileGrid.pageCount > 1 && !panel.quickSettings.editing
                    spacing: 6

                    Repeater {
                        model: tileGrid.pageCount

                        delegate: MouseArea {
                            required property int index

                            width: 12
                            height: 12
                            Accessible.role: Accessible.PageTab
                            Accessible.name: i18nc("@action:button %1 is a page number", "Page %1", index + 1)
                            onClicked: tileGrid.page = index

                            Rectangle {
                                anchors.centerIn: parent
                                width: 6
                                height: 6
                                radius: 3
                                color: Kirigami.Theme.textColor
                                opacity: tileGrid.page === parent.index ? 0.9 : 0.3
                            }
                        }
                    }
                }

                // Brightness of the first screen that has it, as Windows shows one slider.
                Repeater {
                    model: panel.quickSettings.screenBrightness.isBrightnessAvailable ? panel.quickSettings.screenBrightness.displays : null

                    delegate: SliderRow {
                        id: brightnessRow

                        required property int index
                        required property string displayName
                        required property int brightness
                        required property int maxBrightness

                        Layout.fillWidth: true
                        Layout.leftMargin: panel.inset
                        Layout.rightMargin: panel.inset
                        Layout.topMargin: 6
                        visible: index === 0
                        iconName: "brightness-high"
                        accessibleName: i18nc("@label:slider", "Brightness")
                        from: 0
                        to: maxBrightness
                        stepSize: 1
                        value: brightness
                        onMoved: value => panel.quickSettings.screenBrightness.setBrightness(brightnessRow.displayName, Math.round(value))
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: panel.inset
                    Layout.rightMargin: panel.inset
                    Layout.topMargin: 10
                    Layout.bottomMargin: panel.inset + 6
                    visible: panel.quickSettings.hasSink
                    spacing: 12

                    SliderRow {
                        Layout.fillWidth: true
                        iconName: panel.quickSettings.volumeIcon
                        accessibleName: i18nc("@label:slider", "Volume")
                        from: 0
                        to: 100
                        stepSize: panel.quickSettings.volumeStep
                        value: panel.quickSettings.volumePercent
                        onMoved: value => {
                            const sink = panel.quickSettings.sink;
                            sink.muted = false;
                            sink.volume = Math.round(value / 100 * Volume.PulseAudio.NormalVolume);
                        }
                        onIconClicked: panel.quickSettings.sink.muted = !panel.quickSettings.sink.muted
                    }

                    MediaButton {
                        round: true
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        iconName: "orielos-headphones-symbolic"
                        accessibleName: i18nc("@action:button", "Sound output")
                        onClicked: panel.quickSettings.page = "sound"
                    }
                }

                PanelFooter {
                    Layout.fillWidth: true
                    quickSettings: panel.quickSettings
                    inset: panel.inset
                    tiles: tileGrid
                }
            }

            Loader {
                id: subPage

                anchors.fill: parent
                active: panel.quickSettings.page !== ""
                focus: active
                sourceComponent: {
                    switch (panel.quickSettings.page) {
                    case "wifi":
                        return wifiPage;
                    case "bluetooth":
                        return bluetoothPage;
                    case "sound":
                        return soundPage;
                    }
                    return null;
                }
            }
        }
    }

    Component {
        id: wifiPage
        WifiPage {
            quickSettings: panel.quickSettings
            inset: panel.inset
            focus: true
            onBack: panel.quickSettings.page = ""
        }
    }

    Component {
        id: bluetoothPage
        BluetoothPage {
            quickSettings: panel.quickSettings
            inset: panel.inset
            focus: true
            onBack: panel.quickSettings.page = ""
        }
    }

    Component {
        id: soundPage
        SoundPage {
            quickSettings: panel.quickSettings
            inset: panel.inset
            focus: true
            onBack: panel.quickSettings.page = ""
        }
    }
}
