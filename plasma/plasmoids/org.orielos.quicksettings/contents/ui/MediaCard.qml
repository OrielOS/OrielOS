// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.private.mpris as Mpris

// What's playing, on its own card above Quick Settings: the cover, the app, the title and the
// artist, and previous, play or pause, and next.
Card {
    id: card

    required property var player

    readonly property bool playing: card.player?.playbackStatus === Mpris.PlaybackStatus.Playing

    implicitHeight: content.implicitHeight + 28

    RowLayout {
        id: content

        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        Kirigami.ShadowedImage {
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            radius: 8
            source: card.player?.artUrl ?? ""
            sourceSize.width: 128
            sourceSize.height: 128
            fillMode: Image.PreserveAspectCrop
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.5)

            Kirigami.Icon {
                anchors.centerIn: parent
                width: 24
                height: 24
                visible: parent.status !== Image.Ready
                source: card.player?.iconName ?? "media-default-album"
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            PC3.Label {
                Layout.fillWidth: true
                text: card.player?.identity ?? ""
                textFormat: Text.PlainText
                font.pixelSize: 11
                opacity: 0.7
                elide: Text.ElideRight
            }

            PC3.Label {
                Layout.fillWidth: true
                text: card.player?.track ?? ""
                textFormat: Text.PlainText
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: card.player?.artist ?? ""
                textFormat: Text.PlainText
                font.pixelSize: 12
                opacity: 0.7
                elide: Text.ElideRight
            }
        }

        MediaButton {
            iconName: "media-skip-backward"
            accessibleName: i18nc("@action:button", "Previous")
            enabled: card.player?.canGoPrevious ?? false
            onClicked: card.player.Previous()
        }

        MediaButton {
            iconName: card.playing ? "media-playback-pause" : "media-playback-start"
            accessibleName: card.playing ? i18nc("@action:button", "Pause") : i18nc("@action:button", "Play")
            round: true
            enabled: (card.playing ? card.player?.canPause : card.player?.canPlay) ?? false
            onClicked: card.playing ? card.player.Pause() : card.player.Play()
        }

        MediaButton {
            iconName: "media-skip-forward"
            accessibleName: i18nc("@action:button", "Next")
            enabled: card.player?.canGoNext ?? false
            onClicked: card.player.Next()
        }
    }
}
