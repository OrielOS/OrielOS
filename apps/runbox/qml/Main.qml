// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The Run box, as Windows + R shows it in Windows: type a program, folder, document or website and
// OrielOS opens it. The last thing run is ready to run again, and the list holds the ones before.

import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ki18n
import org.orielos.runbox

QQC2.ApplicationWindow {
    id: root

    readonly property RunBoxModel model: RunBoxModel {
        onStarted: Qt.quit()
        onFailed: message => {
            problem.text = message;
            problem.visible = true;
            command.forceActiveFocus();
            command.selectAll();
        }
    }

    function runTyped() {
        if (command.editText.trim().length > 0) {
            problem.visible = false;
            root.model.run(command.editText);
        }
    }

    // A fixed size, as Windows' Run box has, growing only to show a problem.
    readonly property real fixedWidth: Kirigami.Units.gridUnit * 26
    readonly property real fixedHeight: layout.implicitHeight + Kirigami.Units.largeSpacing * 4

    title: KI18n.i18nc("@title:window", "Run")
    width: fixedWidth
    height: fixedHeight
    minimumWidth: fixedWidth
    maximumWidth: fixedWidth
    minimumHeight: fixedHeight
    maximumHeight: fixedHeight
    visible: true
    color: Kirigami.Theme.backgroundColor

    // The box takes the keyboard once the window is active; asking before it shows does nothing.
    onActiveChanged: {
        if (active) {
            // The text field inside the box, which an editable box doesn't focus by itself.
            command.contentItem.forceActiveFocus();
            command.selectAll();
        }
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: Qt.quit()
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing * 2
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignTop
                implicitWidth: Kirigami.Units.iconSizes.medium
                implicitHeight: Kirigami.Units.iconSizes.medium
                source: "system-run"
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: KI18n.i18nc("@info", "Type the name of a program, folder, document or website, and OrielOS will open it for you.")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            QQC2.Label {
                text: KI18n.i18nc("@label:textbox", "Open:")
                textFormat: Text.PlainText
            }

            QQC2.ComboBox {
                id: command

                Layout.fillWidth: true
                editable: true
                model: root.model.history
                Accessible.name: KI18n.i18nc("@label:textbox", "Open:")
                onAccepted: root.runTyped()
                Component.onCompleted: editText = root.model.history.length > 0 ? root.model.history[0] : "";
            }
        }

        Kirigami.InlineMessage {
            id: problem

            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            visible: false
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Item {
                Layout.fillWidth: true
            }

            QQC2.Button {
                text: KI18n.i18nc("@action:button", "OK")
                enabled: command.editText.trim().length > 0 && !root.model.busy
                onClicked: root.runTyped()
            }

            QQC2.Button {
                text: KI18n.i18nc("@action:button", "Cancel")
                onClicked: Qt.quit()
            }

            QQC2.Button {
                text: KI18n.i18nc("@action:button", "Browse…")
                onClicked: browser.open()
            }
        }
    }

    FileDialog {
        id: browser

        title: KI18n.i18nc("@title:window", "Browse")
        currentFolder: StandardPaths.writableLocation(StandardPaths.HomeLocation)
        onAccepted: {
            const path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
            command.editText = path.includes(" ") ? "\"" + path + "\"" : path;
            command.forceActiveFocus();
        }
    }
}
