// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The emoji panel, as Windows + . opens it: emoji with a search and their categories, kaomoji,
// symbols and the clipboard history, each picked with a click or the keyboard. Picking one copies
// it and closes the panel, ready to paste; so does clicking away or Esc, without copying.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import org.kde.plasma.emoji
import org.orielos.emojipanel

import "characters.js" as Characters

QQC2.ApplicationWindow {
    id: root

    // The emoji category shown, or "" for the recent ones.
    property string category: ""
    // Set once the panel has been in use, so losing the focus afterwards closes it.
    property bool wasActive: false

    readonly property real fixedWidth: Kirigami.Units.gridUnit * 22
    readonly property real fixedHeight: Kirigami.Units.gridUnit * 26

    // A list group's title, translated.
    function groupTitle(title: string): string {
        switch (title) {
        case "Happy":
            return KI18n.i18nc("@title:tab A group of kaomoji", "Happy");
        case "Greetings":
            return KI18n.i18nc("@title:tab A group of kaomoji", "Greetings");
        case "Love":
            return KI18n.i18nc("@title:tab A group of kaomoji", "Love");
        case "Sad":
            return KI18n.i18nc("@title:tab A group of kaomoji", "Sad");
        case "Angry":
            return KI18n.i18nc("@title:tab A group of kaomoji", "Angry");
        case "Surprised":
            return KI18n.i18nc("@title:tab A group of kaomoji", "Surprised");
        case "Other":
            return KI18n.i18nc("@title:tab A group of kaomoji", "Other");
        case "Punctuation":
            return KI18n.i18nc("@title:tab A group of symbols", "Punctuation");
        case "Currency":
            return KI18n.i18nc("@title:tab A group of symbols", "Currency");
        case "Arrows":
            return KI18n.i18nc("@title:tab A group of symbols", "Arrows");
        case "Maths":
            return KI18n.i18nc("@title:tab A group of symbols", "Maths");
        case "Latin":
            return KI18n.i18nc("@title:tab A group of symbols", "Latin");
        case "Greek":
            return KI18n.i18nc("@title:tab A group of symbols", "Greek");
        case "Shapes":
            return KI18n.i18nc("@title:tab A group of symbols", "Shapes");
        case "Technical":
            return KI18n.i18nc("@title:tab A group of symbols", "Technical");
        }
        return title;
    }

    // Copies text and closes. The panel hides at once and quits a moment later, once the desktop's
    // clipboard history has taken the text, so it can still be pasted after the panel has gone.
    function pick(text: string, isEmoji: bool) {
        if (isEmoji) {
            recent.includeRecent(text);
        }
        clipboard.copy(text);
        root.visible = false;
        quitLater.start();
    }

    title: KI18n.i18nc("@title:window", "Emoji Panel")
    width: fixedWidth
    height: fixedHeight
    minimumWidth: fixedWidth
    maximumWidth: fixedWidth
    minimumHeight: fixedHeight
    maximumHeight: fixedHeight
    visible: true
    color: Kirigami.Theme.backgroundColor

    onActiveChanged: {
        if (active) {
            root.wasActive = true;
            if (tabs.currentIndex === 0) {
                searchField.forceActiveFocus();
            }
        } else if (root.wasActive && root.visible) {
            Qt.quit();
        }
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: Qt.quit()
    }

    Timer {
        id: quitLater

        interval: 500
        onTriggered: Qt.quit()
    }

    EmojiModel {
        id: emoji
    }

    RecentEmojiModel {
        id: recent
    }

    ClipboardHistory {
        id: clipboard
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        QQC2.TabBar {
            id: tabs

            Layout.fillWidth: true

            QQC2.TabButton {
                text: KI18n.i18nc("@title:tab", "Emoji")
            }
            QQC2.TabButton {
                text: KI18n.i18nc("@title:tab", "Kaomoji")
            }
            QQC2.TabButton {
                text: KI18n.i18nc("@title:tab", "Symbols")
            }
            QQC2.TabButton {
                text: KI18n.i18nc("@title:tab", "Clipboard")
                onClicked: clipboard.refresh()
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            // Emoji: a search, the categories and the emoji in the one chosen.
            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                Kirigami.SearchField {
                    id: searchField

                    Layout.fillWidth: true
                    placeholderText: KI18n.i18nc("@info:placeholder", "Search emoji")
                    KeyNavigation.down: emojiGrid
                    onAccepted: {
                        if (emojiGrid.count > 0) {
                            emojiGrid.currentIndex = 0;
                            (emojiGrid.currentItem as QQC2.AbstractButton)?.clicked();
                        }
                    }
                }

                ListView {
                    id: categories

                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                    visible: searchField.text.length === 0
                    orientation: ListView.Horizontal
                    spacing: 0
                    clip: true
                    model: [""].concat(emoji.categories)

                    // Recently used, then each category, shown by its first emoji.
                    delegate: QQC2.AbstractButton {
                        id: categoryButton

                        required property string modelData
                        readonly property bool recentOnes: modelData.length === 0
                        readonly property string label: recentOnes ? KI18n.i18nc("@action:button", "Recently used") : modelData

                        width: Kirigami.Units.gridUnit * 2
                        height: width
                        padding: Kirigami.Units.smallSpacing
                        hoverEnabled: true
                        Accessible.name: categoryButton.label
                        Accessible.role: Accessible.PageTab
                        Accessible.checked: root.category === modelData
                        QQC2.ToolTip.text: categoryButton.label
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        onClicked: root.category = modelData

                        contentItem: Item {
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: Kirigami.Units.iconSizes.smallMedium
                                height: width
                                visible: categoryButton.recentOnes
                                source: "document-open-recent"
                            }

                            Text {
                                anchors.fill: parent
                                visible: !categoryButton.recentOnes
                                text: categoryButton.recentOnes ? "" : emoji.findFirstEmojiForCategory(categoryButton.modelData)
                                textFormat: Text.PlainText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                fontSizeMode: Text.Fit
                                minimumPixelSize: Kirigami.Theme.smallFont.pixelSize
                                font.pixelSize: Kirigami.Units.gridUnit
                                font.family: "emoji"
                            }
                        }

                        background: Rectangle {
                            radius: Kirigami.Units.cornerRadius
                            color: root.category === categoryButton.modelData ? Qt.alpha(Kirigami.Theme.highlightColor, 0.3)
                                : (categoryButton.hovered ? Qt.alpha(Kirigami.Theme.highlightColor, 0.15) : "transparent")
                        }
                    }
                }

                CharacterGrid {
                    id: emojiGrid

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    emoji: true
                    model: searchField.text.length > 0 ? searchResults : (root.category.length === 0 ? recent : inCategory)
                    onPicked: text => root.pick(text, true)

                    SearchModelFilter {
                        id: searchResults

                        sourceModel: emoji
                        search: searchField.text
                    }

                    CategoryModelFilter {
                        id: inCategory

                        sourceModel: emoji
                        category: root.category
                    }

                    Kirigami.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 4
                        visible: emojiGrid.count === 0
                        text: searchField.text.length > 0 ? KI18n.i18nc("@info", "No emoji found") : KI18n.i18nc("@info", "No emoji used yet")
                    }
                }

                // Opens on the recent emoji, or the smileys while there are none: the category that
                // starts with the grinning face, whatever the language calls it.
                Component.onCompleted: {
                    if (recent.count === 0 && emoji.categories.length > 0) {
                        const smileys = emoji.categories.find(category => emoji.findFirstEmojiForCategory(category) === "\u{1F600}");
                        root.category = smileys ?? emoji.categories[0];
                    }
                }
            }

            // Kaomoji and symbols: the groups, and the characters in the one chosen.
            Repeater {
                model: [
                    { groups: Characters.kaomoji, wide: true },
                    { groups: Characters.symbols, wide: false }
                ]

                delegate: ColumnLayout {
                    id: listPage

                    required property var modelData
                    required property int index
                    property int group: 0

                    spacing: Kirigami.Units.smallSpacing

                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Repeater {
                            model: listPage.modelData.groups

                            delegate: QQC2.Button {
                                required property var modelData
                                required property int index

                                flat: true
                                checkable: true
                                checked: listPage.group === index
                                text: root.groupTitle(modelData.title)
                                onClicked: listPage.group = index
                            }
                        }
                    }

                    CharacterGrid {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        wide: listPage.modelData.wide
                        model: listPage.modelData.groups[listPage.group].items
                        onPicked: text => root.pick(text, false)
                    }
                }
            }

            // The clipboard history, newest first.
            ListView {
                id: history

                clip: true
                model: clipboard.items
                keyNavigationEnabled: true
                activeFocusOnTab: true
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                delegate: QQC2.ItemDelegate {
                    id: item

                    required property string modelData

                    width: ListView.view.width
                    highlighted: ListView.isCurrentItem && history.activeFocus
                    Accessible.name: modelData

                    contentItem: QQC2.Label {
                        text: item.modelData.trim()
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    onClicked: root.pick(item.modelData, false)
                }

                Keys.onReturnPressed: (currentItem as QQC2.AbstractButton)?.clicked()
                Keys.onEnterPressed: (currentItem as QQC2.AbstractButton)?.clicked()

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    visible: history.count === 0
                    icon.name: "edit-paste"
                    text: clipboard.available ? KI18n.i18nc("@info", "Nothing copied yet") : KI18n.i18nc("@info", "The clipboard history is turned off")
                    explanation: clipboard.available ? KI18n.i18nc("@info", "Text you copy shows up here.") : KI18n.i18nc("@info", "Turn it on in the system tray's Clipboard settings.")
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: KI18n.i18nc("@info", "Pick one to copy it, then paste it with Ctrl+V.")
        }
    }
}
