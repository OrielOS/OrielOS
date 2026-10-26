// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Asks before a change that replaces or removes a whole version of OrielOS. Cancel takes the focus
// when it opens, so a key press never confirms by accident. The buttons are plain buttons rather
// than actions, so the mnemonic in their text works.

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.PromptDialog {
    id: dialog

    required property string actionText
    required property string actionIcon
    required property string cancelText

    signal confirmed

    // Without it nothing in the popup can take the keyboard focus, and Esc doesn't reach it.
    focus: true
    standardButtons: QQC2.Dialog.NoButton
    footer: QQC2.DialogButtonBox {
        leftPadding: Kirigami.Units.largeSpacing
        rightPadding: Kirigami.Units.largeSpacing
        bottomPadding: Kirigami.Units.largeSpacing
        topPadding: Kirigami.Units.smallSpacing

        onAccepted: {
            dialog.close();
            dialog.confirmed();
        }
        onRejected: dialog.close()

        QQC2.Button {
            id: cancelButton

            QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.RejectRole
            text: dialog.cancelText
            icon.name: "dialog-cancel"
        }

        QQC2.Button {
            QQC2.DialogButtonBox.buttonRole: QQC2.DialogButtonBox.AcceptRole
            text: dialog.actionText
            icon.name: dialog.actionIcon
        }
    }

    onOpened: cancelButton.forceActiveFocus()
}
