/*
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: GPL-3.0-or-later
*/

// The welcome screen between signing in and the desktop. It carries on from the sign-in screen
// (image/sddm/orielos/Main.qml): the same blurred wallpaper, with the account picture and name in
// the same place, and a thin line where the password box was that fills as Plasma's splash program
// raises `stage`; the program closes the window once the desktop is ready. Everyday sign-ins show
// no words. The first sign-in's screen (org.orielos.firstsignin) is this one with a message.

import QtQuick
import QtQuick.Layouts

import org.kde.breeze.components
import org.kde.coreaddons as KCoreAddons
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Rectangle {
    id: root

    property int stage
    // What it says under the line, if anything.
    property string message

    color: "#0C1530"

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    KCoreAddons.KUser {
        id: user
    }

    readonly property string realName: user.fullName || user.loginName

    Image {
        id: wallpaper
        anchors.fill: parent
        source: "file:///usr/share/wallpapers/OrielOS/contents/images_dark/3840x2160.jpg"
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
    }

    // The sign-in screen's blur, already at full strength. With no state, the fader animates
    // nothing; its states only fade the sign-in screen's parts, which this screen doesn't have.
    WallpaperFader {
        anchors.fill: parent
        source: wallpaper
        state: ""
        factor: 1
    }

    ColumnLayout {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * 0.26)
        spacing: 0

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7 + 16
            Layout.preferredHeight: Kirigami.Units.gridUnit * 7 + 16
            radius: width / 2
            color: Qt.rgba(156 / 255, 194 / 255, 1, 0.10)

            AccountPicture {
                anchors.fill: parent
                anchors.margins: 8
                source: user.faceIconUrl.toString()
                name: root.realName
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 7
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.35)
            }
        }

        PlasmaComponents3.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.gridUnit
            text: root.realName
            textFormat: Text.PlainText
            color: "#FFFFFF"
            font.family: "Noto Sans Display"
            font.pixelSize: 30
            font.weight: Font.Bold
        }

        // Where the password box was: the same height, so nothing moves.
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.gridUnit * 1.5
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3

            // The line: the account picture's ring colour over a faint track, filling as the
            // desktop starts. Plasma raises `stage` to 6 when it is ready.
            Rectangle {
                id: track
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(parent.height / 2) - (root.message ? Kirigami.Units.gridUnit : 0)
                width: 120
                height: 3
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.18)

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: "#9CC2FF"
                    width: parent.width * Math.max(0.08, Math.min(root.stage, 6) / 6)

                    Behavior on width {
                        NumberAnimation {
                            duration: Kirigami.Units.veryLongDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
            PlasmaComponents3.Label {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: track.bottom
                anchors.topMargin: Kirigami.Units.gridUnit
                visible: text.length > 0
                text: root.message
                textFormat: Text.PlainText
                color: Qt.rgba(1, 1, 1, 0.85)
                font.pixelSize: 16
            }
        }
    }
}
