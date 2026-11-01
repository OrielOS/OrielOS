// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The Windows + P panel: Sill's card with the four ways to use the screens, the one in use marked.
// Up and Down or Windows + P move the selection, Enter or a click applies it, Escape or clicking
// elsewhere closes the panel.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import org.orielos.displaymode

Window {
    id: root

    // The row the keyboard is on, and the choices in DisplayLayout::Mode's order.
    property int selected: -1
    readonly property var choices: [
        { text: KI18n.i18nc("@action:button Use only this computer's own screen", "PC screen only"), icon: "osd-shutd-screen" },
        { text: KI18n.i18nc("@action:button Show the same picture on every screen", "Duplicate"), icon: "osd-duplicate" },
        { text: KI18n.i18nc("@action:button Spread the desktop across the screens", "Extend"), icon: "osd-sbs-sright" },
        { text: KI18n.i18nc("@action:button Use only the other screens", "Second screen only"), icon: "osd-shutd-laptop" },
    ]
    readonly property bool hasSecondScreen: switcher.screenCount > 1
    property bool wasActive: false

    // Moves to the next choice, as pressing Windows + P again does.
    function next() {
        const count = root.hasSecondScreen ? root.choices.length : 1;
        root.selected = (Math.max(root.selected, 0) + 1) % count;
        root.requestActivate();
    }

    function choose(mode: int) {
        if (mode === switcher.currentMode || (mode > 0 && !root.hasSecondScreen)) {
            Qt.quit();
            return;
        }
        switcher.apply(mode);
    }

    title: KI18n.i18nc("@title:window", "Display mode")
    flags: Qt.FramelessWindowHint
    color: "transparent"
    width: 360
    height: card.implicitHeight
    visible: false

    onActiveChanged: {
        if (root.active) {
            root.wasActive = true;
        } else if (root.wasActive) {
            Qt.quit();
        }
    }

    DisplaySwitcher {
        id: switcher

        onChanged: {
            if (root.selected < 0) {
                root.selected = switcher.currentMode;
            }
        }
        onApplied: Qt.quit()
        onUnavailable: Qt.quit()
    }

    Rectangle {
        id: card

        anchors.fill: parent
        implicitHeight: content.implicitHeight
        radius: 8
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.94)
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.13)
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        focus: true
        Keys.onEscapePressed: Qt.quit()
        Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
        Keys.onDownPressed: root.selected = Math.min((root.hasSecondScreen ? root.choices.length : 1) - 1, root.selected + 1)
        Keys.onReturnPressed: root.choose(root.selected)
        Keys.onEnterPressed: root.choose(root.selected)

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 2

            QQC2.Label {
                Layout.fillWidth: true
                Layout.margins: 20
                Layout.bottomMargin: 8
                text: KI18n.i18nc("@title", "Display mode")
                textFormat: Text.PlainText
                font.pixelSize: 14
                font.weight: Font.DemiBold
                Accessible.role: Accessible.Heading
            }

            Repeater {
                model: root.choices

                delegate: QQC2.AbstractButton {
                    id: choice

                    required property int index
                    required property var modelData

                    readonly property bool current: switcher.ready && switcher.currentMode === index

                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    implicitHeight: 56
                    enabled: index === 0 || root.hasSecondScreen
                    text: modelData.text
                    Accessible.role: Accessible.RadioButton
                    Accessible.checkable: true
                    Accessible.checked: current
                    onClicked: root.choose(index)
                    onHoveredChanged: {
                        if (hovered) {
                            root.selected = index;
                        }
                    }

                    background: Rectangle {
                        radius: 6
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b,
                            choice.pressed ? 0.12 : (root.selected === choice.index ? 0.08 : 0))

                        // The mode in use, marked as Quick Settings marks the network in use.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: 16
                            radius: 1.5
                            visible: choice.current
                            color: Kirigami.Theme.highlightColor
                        }
                    }

                    contentItem: RowLayout {
                        spacing: 14
                        opacity: choice.enabled ? 1 : 0.4

                        Kirigami.Icon {
                            Layout.leftMargin: 12
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            source: choice.modelData.icon
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            text: choice.text
                            textFormat: Text.PlainText
                            font.pixelSize: 13
                            font.weight: choice.current ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 20
                Layout.topMargin: 4
                visible: switcher.ready && !root.hasSecondScreen
                text: KI18n.i18nc("@info", "Connect another screen to use the other choices.")
                textFormat: Text.PlainText
                font.pixelSize: 12
                opacity: 0.7
                wrapMode: Text.Wrap
            }

            // Sill's footer band, with a link to the screens' page in Settings.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 12
                implicitHeight: 48
                radius: 8
                color: Qt.rgba(0, 0, 0, 0.18)

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 8
                    color: Qt.rgba(0, 0, 0, 0.18)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 1
                    color: Kirigami.Theme.textColor
                    opacity: 0.08
                }

                QQC2.ToolButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: KI18n.i18nc("@action:button", "Display settings")
                    font.pixelSize: 12
                    onClicked: {
                        Qt.openUrlExternally("orielos-settings:display");
                        Qt.quit();
                    }
                }
            }
        }
    }
}
