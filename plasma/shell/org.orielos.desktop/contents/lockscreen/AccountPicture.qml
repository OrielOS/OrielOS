/*
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: GPL-3.0-or-later
*/

// A round account picture: the user's photo, or the first letter of their name on OrielOS's blue
// gradient when they have none.

import QtQuick
import Qt5Compat.GraphicalEffects

import org.kde.plasma.components as PlasmaComponents3

Item {
    id: picture

    property string source
    property string name

    Accessible.ignored: true

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        visible: photo.status !== Image.Ready
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#9CC2FF" }
            GradientStop { position: 0.55; color: "#3A66F0" }
            GradientStop { position: 1.0; color: "#1F3BB0" }
        }

        PlasmaComponents3.Label {
            anchors.centerIn: parent
            text: picture.name.length > 0 ? picture.name.charAt(0).toUpperCase() : ""
            color: "#FFFFFF"
            font.family: "Noto Sans Display"
            font.weight: Font.Bold
            font.pixelSize: Math.round(picture.height * 0.42)
        }
    }

    Image {
        id: photo
        anchors.fill: parent
        source: picture.source
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectCrop
        visible: false
    }

    OpacityMask {
        anchors.fill: parent
        source: photo
        visible: photo.status === Image.Ready
        maskSource: Rectangle {
            width: photo.width
            height: photo.height
            radius: width / 2
        }
    }
}
