// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

// Sill's small pill button beside a heading, such as All apps, More and Back: a 12 px label with a
// chevron after it, or before it when it goes back.
PC3.ToolButton {
    id: pill

    // Whether the chevron points back, before the label.
    property bool back: false
    readonly property bool rightToLeft: Application.layoutDirection === Qt.RightToLeft

    Accessible.name: text
    Accessible.role: Accessible.Button
    leftPadding: back ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.largeSpacing
    rightPadding: back ? Kirigami.Units.largeSpacing : Kirigami.Units.smallSpacing * 2
    topPadding: Kirigami.Units.smallSpacing
    bottomPadding: Kirigami.Units.smallSpacing

    background: Rectangle {
        implicitHeight: 26
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b,
                       pill.down ? 0.18 : (pill.hovered ? 0.14 : 0.08))
        border.width: pill.visualFocus ? 2 : 0
        border.color: Kirigami.Theme.highlightColor
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing
        layoutDirection: pill.back ? Qt.RightToLeft : Qt.LeftToRight

        PC3.Label {
            text: pill.text
            textFormat: Text.PlainText
            font.pixelSize: 12
        }

        Kirigami.Icon {
            Layout.preferredWidth: 12
            Layout.preferredHeight: 12
            source: pill.back !== pill.rightToLeft ? "go-previous" : "go-next"
        }
    }

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
}
