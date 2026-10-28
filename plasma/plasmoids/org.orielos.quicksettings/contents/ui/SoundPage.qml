// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.volume as Volume

// Quick Settings' sound page: the sound outputs, the one in use marked, switched with one click;
// then the volume mixer, a slider for each app playing sound. Uses Plasma's sound services, as
// Plasma's own volume widget does.
SubPage {
    id: page

    title: i18nc("@title", "Sound output")
    moreText: i18nc("@action:button", "More sound settings")
    morePage: "sound"

    function name(pulseObject: var): string {
        return pulseObject.description || pulseObject.name || "";
    }

    Volume.PulseObjectFilterModel {
        id: outputs
        filterOutInactiveDevices: true
        filterVirtualDevices: true
        sourceModel: Volume.SinkModel {}
    }

    Volume.PulseObjectFilterModel {
        id: streams
        filters: [
            { role: "VirtualStream", value: false },
            { role: "Client", value: client => !client || client.name !== "libcanberra" },
        ]
        sourceModel: Volume.SinkInputModel {}
    }

    Flickable {
        id: flick

        anchors.fill: parent
        anchors.leftMargin: page.inset - 8
        anchors.rightMargin: page.inset - 8
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        PC3.ScrollBar.vertical: PC3.ScrollBar {}

        ColumnLayout {
            id: column

            width: flick.width
            spacing: 2

            Repeater {
                model: outputs

                delegate: ListRow {
                    id: output

                    required property var model

                    Layout.fillWidth: true
                    text: page.name(output.model.PulseObject)
                    iconName: ["headphone", "headset", "hands-free"].includes(output.model.PulseObject.formFactor) ? "audio-headphones" : "audio-speakers"
                    current: output.model.PulseObject.default
                    Accessible.role: Accessible.RadioButton
                    Accessible.checkable: true
                    Accessible.checked: current
                    onClicked: output.model.PulseObject.default = true
                }
            }

            PC3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.topMargin: 12
                Layout.bottomMargin: 4
                visible: streams.count > 0
                text: i18nc("@title:group", "Volume mixer")
                textFormat: Text.PlainText
                font.pixelSize: 12
                font.weight: Font.DemiBold
                Accessible.role: Accessible.Heading
            }

            Repeater {
                model: streams

                delegate: ColumnLayout {
                    id: stream

                    required property var model

                    readonly property string label: {
                        const client = stream.model.Client;
                        if (client && client.name && client.name !== "pipewire-media-session") {
                            return client.name;
                        }
                        return stream.model.Name || i18nc("@label an app playing sound whose name isn't known", "App");
                    }

                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    Layout.bottomMargin: 6
                    spacing: 0

                    PC3.Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: 40
                        text: stream.label
                        textFormat: Text.PlainText
                        font.pixelSize: 11
                        opacity: 0.8
                        elide: Text.ElideRight
                    }

                    SliderRow {
                        Layout.fillWidth: true
                        iconName: stream.model.IconName || "audio-volume-high"
                        accessibleName: i18nc("@label:slider %1 is an app", "%1 volume", stream.label)
                        from: 0
                        to: 100
                        stepSize: page.quickSettings.volumeStep
                        value: Math.round(stream.model.Volume / Volume.PulseAudio.NormalVolume * 100)
                        onMoved: value => {
                            stream.model.PulseObject.muted = false;
                            stream.model.PulseObject.volume = Math.round(value / 100 * Volume.PulseAudio.NormalVolume);
                        }
                        onIconClicked: stream.model.PulseObject.muted = !stream.model.PulseObject.muted
                    }
                }
            }
        }
    }

    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - 2 * page.inset
        visible: outputs.count === 0
        iconName: "audio-volume-muted"
        text: i18nc("@info:placeholder", "No sound outputs found")
    }
}
