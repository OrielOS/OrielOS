/*
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: GPL-3.0-or-later
*/

// Under the box, as Windows has: for an account with a PIN, "I forgot my PIN" and "Sign-in options",
// which shows a button for each way in (PIN and password) to switch the box between them. Whether the
// account has a PIN, and how long it is, comes from the note OrielOS's PIN service keeps in
// /var/lib/orielos/pin-info; the box signs in on the PIN's last digit. The lock screen has the same
// in a copy of this file (plasma/shell/org.orielos.desktop/contents/lockscreen/SignInOptions.qml);
// keep the two the same.

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

ColumnLayout {
    id: options

    // The account's login name.
    property string loginName
    property string domain

    readonly property int pinLength: pinInfo.status === Loader.Ready && pinInfo.item ? pinInfo.item.pinLength : 0
    readonly property bool hasPin: pinLength > 0
    // Whether the box takes the PIN (true) or the password.
    property bool pinMode: hasPin

    // "I forgot my PIN": the box switches to the password.
    signal forgotPin()

    spacing: Kirigami.Units.smallSpacing
    visible: hasPin

    onHasPinChanged: pinMode = hasPin

    Loader {
        id: pinInfo
        active: options.loginName !== ""
        source: active ? "file:///var/lib/orielos/pin-info/" + options.loginName + ".qml" : ""
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.largeSpacing

        PlasmaComponents3.ToolButton {
            visible: options.pinMode
            text: i18ndc(options.domain, "@action:button", "I forgot my PIN")
            font.pixelSize: 12
            onClicked: {
                options.pinMode = false;
                options.forgotPin();
            }
        }
        PlasmaComponents3.ToolButton {
            id: optionsButton
            text: i18ndc(options.domain, "@action:button", "Sign-in options")
            checkable: true
            font.pixelSize: 12
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        visible: optionsButton.checked
        spacing: Kirigami.Units.largeSpacing

        component Method: PlasmaComponents3.ToolButton {
            required property bool pin
            Layout.preferredWidth: Kirigami.Units.gridUnit * 2.4
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.4
            display: PlasmaComponents3.AbstractButton.IconOnly
            checkable: true
            checked: options.pinMode === pin
            onClicked: {
                options.pinMode = pin;
                optionsButton.checked = false;
            }
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered
        }

        Method {
            pin: true
            icon.name: "orielos-pin-symbolic"
            text: i18ndc(options.domain, "@action:button sign in with", "PIN")
        }
        Method {
            pin: false
            icon.name: "orielos-password-symbolic"
            text: i18ndc(options.domain, "@action:button sign in with", "Password")
        }
    }
}
