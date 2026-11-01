// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// A grid of characters to pick from: emoji from one of Plasma's emoji models, or kaomoji and
// symbols from a list. Each cell is a button with the character, and its name as the tooltip when
// the model has one; picking one emits picked.

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

GridView {
    id: grid

    // Wide cells for kaomoji, which are several characters long.
    property bool wide: false
    // Emoji are drawn in the colour emoji font, symbols in the usual one.
    property bool emoji: false
    // The characters' size in the cells.
    property real glyphSize: Kirigami.Units.gridUnit * 1.4

    signal picked(string text)

    clip: true
    keyNavigationEnabled: true
    cellWidth: wide ? Math.floor(width / 3) : Kirigami.Units.gridUnit * 2.5
    cellHeight: wide ? Kirigami.Units.gridUnit * 2.5 : cellWidth
    currentIndex: -1
    activeFocusOnTab: true
    QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

    Keys.onReturnPressed: (currentItem as QQC2.AbstractButton)?.clicked()
    Keys.onEnterPressed: (currentItem as QQC2.AbstractButton)?.clicked()

    delegate: QQC2.AbstractButton {
        id: cell

        // A model's characters are in display, and an emoji's name in toolTip; a list's in
        // modelData.
        required property var model
        required property int index
        readonly property string glyph: cell.model.display ?? cell.model.modelData ?? ""
        readonly property string name: cell.model.toolTip ?? ""
        readonly property bool current: GridView.isCurrentItem && grid.activeFocus

        width: grid.cellWidth
        height: grid.cellHeight
        padding: Kirigami.Units.smallSpacing / 2
        hoverEnabled: true
        Accessible.name: cell.name.length > 0 ? cell.name : cell.glyph
        Accessible.role: Accessible.Button
        QQC2.ToolTip.text: cell.name
        QQC2.ToolTip.visible: hovered && cell.name.length > 0
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

        // The character fills the cell, shrinking to fit when it's wider.
        contentItem: Text {
            text: cell.glyph
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Kirigami.Theme.textColor
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Kirigami.Theme.smallFont.pixelSize
            font.pixelSize: grid.wide ? Kirigami.Theme.defaultFont.pixelSize * 1.1 : grid.glyphSize
            font.family: grid.emoji ? "emoji" : Kirigami.Theme.defaultFont.family
        }

        background: Rectangle {
            radius: Kirigami.Units.cornerRadius
            color: cell.pressed ? Qt.alpha(Kirigami.Theme.highlightColor, 0.4)
                : (cell.hovered || cell.current ? Qt.alpha(Kirigami.Theme.highlightColor, 0.2) : "transparent")
            border.width: cell.current ? 1 : 0
            border.color: Kirigami.Theme.highlightColor
        }

        onClicked: grid.picked(cell.glyph)
    }
}
