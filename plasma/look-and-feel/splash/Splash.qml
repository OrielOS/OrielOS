/*
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: GPL-3.0-or-later
*/

// The welcome screen between signing in and the desktop. It carries on from the sign-in screen
// (image/sddm/orielos/Main.qml): the same blurred wallpaper, with the account picture and name in
// the same place, and a spinner and "Welcome" where the password box was. Plasma's splash program
// sets `stage` as the desktop starts and closes the window once it is ready. The first sign-in's
// screen (org.orielos.firstsignin) is this one with another message.

import QtQuick
import QtQuick.Layouts

import org.kde.breeze.components
import org.kde.coreaddons as KCoreAddons
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Rectangle {
    id: root

    property int stage
    // What it says beside the spinner.
    property string message: i18ndc("plasma_lookandfeel_org.kde.lookandfeel", "@info:status shown while the desktop starts after signing in", "Welcome")

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
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.gridUnit * 1.5
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.BusyIndicator {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                running: root.stage < 6
            }
            PlasmaComponents3.Label {
                text: root.message
                textFormat: Text.PlainText
                color: "#FFFFFF"
                font.pixelSize: 20
            }
        }
    }
}
