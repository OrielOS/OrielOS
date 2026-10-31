/*
    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

// OrielOS's sign-in screen, in Sill's style, built on Breeze's (sddm-breeze 6.7.5, Main.qml). The
// sign-in shows from the moment the screen appears, over the blurred wallpaper: the chosen
// account's picture and name and a rounded password box. Every account is listed at the bottom
// left, with Other user for typing a name; the keyboard layout, the on-screen keyboard, a power
// menu (Sleep, Restart, Shut down; no Hibernate, which OrielOS doesn't offer) and the battery are
// at the bottom right. Breeze's other files come from its theme unchanged, copied at build time
// (image/build/28-sign-in.sh), which stops the build if Breeze's Main.qml changes. Keep the look in
// step with the lock screen (plasma/shell/org.orielos.desktop/contents/lockscreen/).

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami

import org.kde.breeze.components

Item {
    id: root

    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary
    Kirigami.Theme.inherit: false

    width: 1600
    height: 900

    property string notificationMessage
    // With "press Ctrl+Alt+Delete to sign in" on, the sign-in shows only after those keys, which no
    // app can fake.
    property bool ctrlAltDelPressed: String(config.requireCtrlAltDel) !== "true"
    // The account the sign-in is for: an index in userModel, or -1 for Other user.
    property int currentUser: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    readonly property bool otherUser: currentUser < 0 || userModel.count === 0
    readonly property string currentName: otherUser ? "" : userModelData(currentUser, "name")
    readonly property string currentRealName: otherUser ? "" : (userModelData(currentUser, "realName") || currentName)
    readonly property string currentIcon: otherUser ? "" : photo(userModelData(currentUser, "icon"))

    // SDDM's stand-in face for accounts without a photo; those show their initial instead.
    function photo(icon) {
        return String(icon).endsWith("/.face.icon") ? "" : icon;
    }

    function userModelData(index, role) {
        return userModel.data(userModel.index(index, 0), Qt.UserRole + 1 + ["name", "realName", "homeDir", "icon", "needsPassword"].indexOf(role)) ?? "";
    }

    function login() {
        const name = root.otherUser ? userNameBox.text : root.currentName;
        if (name === "") {
            userNameBox.forceActiveFocus();
            return;
        }
        root.notificationMessage = "";
        submitButton.forceActiveFocus();
        if (lockout.phrase !== "") {
            if (!lockout.answer(passwordBox.text)) {
                shake.start();
            }
            passwordBox.text = "";
            passwordBox.forceActiveFocus();
            return;
        }
        sddm.login(name, passwordBox.text, sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0);
    }

    function choose(index) {
        root.currentUser = index;
        passwordBox.text = "";
        (root.otherUser ? userNameBox : passwordBox).forceActiveFocus();
    }

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    // Slows down guessing after repeated wrong passwords.
    Lockout {
        id: lockout
    }

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    Item {
        id: wallpaper
        anchors.fill: parent
        Repeater {
            model: screenModel

            Background {
                x: geometry.x
                y: geometry.y
                width: geometry.width
                height: geometry.height
                sceneBackgroundType: config.type
                sceneBackgroundColor: config.color
                sceneBackgroundImage: config.background
            }
        }
    }

    WallpaperFader {
        visible: config.type === "image"
        anchors.fill: parent
        state: "on"
        source: wallpaper
        mainStack: signIn
        footer: footer
        clock: faderClock
    }

    // WallpaperFader fades a clock, which this sign-in screen doesn't show.
    Item {
        id: faderClock
        property Item shadow: Item {}
        visible: false
    }

    // A StackView, as Breeze's, because WallpaperFader and the on-screen keyboard expect one.
    FocusScope {
        anchors.fill: parent
        visible: !root.ctrlAltDelPressed
        focus: visible

        PlasmaComponents3.Label {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(root.height * 0.45)
            text: i18ndc("plasma-desktop-sddm-theme", "@info:usagetip", "Press Ctrl+Alt+Delete to sign in")
            textFormat: Text.PlainText
            color: "#FFFFFF"
            font.pixelSize: 20
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.AltModifier)) {
                root.ctrlAltDelPressed = true;
                (root.otherUser ? userNameBox : passwordBox).forceActiveFocus();
            }
            event.accepted = true;
        }
    }

    QQC2.StackView {
        id: signIn
        anchors.fill: parent
        visible: root.ctrlAltDelPressed
        focus: visible

        initialItem: FocusScope {
            id: signInPage
            focus: true

            // The y position kept visible above the on-screen keyboard.
            readonly property int visibleBoundary: column.y + passwordField.y + passwordField.height + Kirigami.Units.smallSpacing

            Timer {
                // SDDM may not give the window focus until after it shows.
                running: root.ctrlAltDelPressed
                interval: 200
                onTriggered: (root.otherUser ? userNameBox : passwordBox).forceActiveFocus()
            }

            ColumnLayout {
                id: column
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(root.height * 0.26)
                width: Math.min(Kirigami.Units.gridUnit * 22, root.width - Kirigami.Units.gridUnit * 2)
                spacing: 0

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7 + 16
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 7 + 16
                    radius: width / 2
                    color: Qt.rgba(156 / 255, 194 / 255, 1, 0.10)
                    Accessible.ignored: true

                    AccountPicture {
                        anchors.fill: parent
                        anchors.margins: 8
                        source: root.currentIcon
                        name: root.otherUser ? "?" : root.currentRealName
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
                    text: root.otherUser ? i18ndc("plasma-desktop-sddm-theme", "@action:button For switching to a username and password prompt", "Other…").replace("…", "") : root.currentRealName
                    textFormat: Text.PlainText
                    font.family: "Noto Sans Display"
                    font.pixelSize: 30
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                PillField {
                    id: userNameField
                    visible: root.otherUser
                    focused: userNameBox.activeFocus
                    Layout.topMargin: Kirigami.Units.gridUnit * 1.5

                    PlasmaComponents3.TextField {
                        id: userNameBox
                        Layout.fillWidth: true
                        background: null
                        font.pixelSize: 15
                        placeholderText: i18ndc("plasma-desktop-sddm-theme", "@info:placeholder in text field", "Username")
                        inputMethodHints: Qt.ImhNoAutoUppercase
                        onAccepted: passwordBox.forceActiveFocus()
                    }
                }

                PillField {
                    id: passwordField
                    focused: passwordBox.activeFocus
                    Layout.topMargin: root.otherUser ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.gridUnit * 1.5

                    RejectPasswordAnimation {
                        id: shake
                        target: passwordField
                    }

                    PlasmaExtras.PasswordField {
                        id: passwordBox
                        Layout.fillWidth: true
                        background: null
                        font.pixelSize: 15
                        placeholderText: lockout.phrase !== ""
                            ? i18ndc("plasma-desktop-sddm-theme", "@info:placeholder in text field, %1 is a phrase such as A1B2C3", "Type %1", lockout.phrase)
                            : i18ndc("plasma-desktop-sddm-theme", "@info:placeholder in text field", "Password")
                        enabled: lockout.secondsLeft === 0
                        onAccepted: root.login()

                        // The phrase is shown as it's typed.
                        Binding on showPassword {
                            value: true
                            when: lockout.phrase !== ""
                            restoreMode: Binding.RestoreBindingOrValue
                        }
                    }

                    PlasmaComponents3.ToolButton {
                        id: submitButton
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 2.2
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 2.2
                        icon.name: LayoutMirroring.enabled ? "go-previous" : "go-next"
                        display: PlasmaComponents3.AbstractButton.IconOnly
                        text: i18ndc("plasma-desktop-sddm-theme", "@action:button", "Log In")
                        onClicked: root.login()
                        Keys.onEnterPressed: clicked()
                        Keys.onReturnPressed: clicked()
                    }
                }

                PlasmaComponents3.Label {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Kirigami.Units.smallSpacing * 2
                    Layout.preferredWidth: passwordField.Layout.preferredWidth
                    text: {
                        const parts = [];
                        if (lockout.phrase !== "") {
                            parts.push(i18ndc("plasma-desktop-sddm-theme", "@info:status", "Too many wrong passwords. Type the characters shown to carry on."));
                        } else if (lockout.secondsLeft > 0) {
                            parts.push(i18ndcp("plasma-desktop-sddm-theme", "@info:status", "Try again in %1 second.", "Try again in %1 seconds.", lockout.secondsLeft));
                        }
                        if (capsLockState.locked) {
                            parts.push(i18ndc("plasma-desktop-sddm-theme", "@info:status", "Caps Lock is on"));
                        }
                        if (root.notificationMessage) {
                            parts.push(root.notificationMessage);
                        }
                        return parts.join(" • ");
                    }
                    textFormat: Text.PlainText
                    color: "#C9D6F5"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    component PillField: Rectangle {
        default property alias content: row.data
        Layout.alignment: Qt.AlignHCenter
        property bool focused: false
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
        radius: height / 2
        color: Qt.rgba(12 / 255, 21 / 255, 48 / 255, 0.55)
        border.width: 1
        border.color: focused ? Qt.rgba(156 / 255, 194 / 255, 1, 0.8) : Qt.rgba(1, 1, 1, 0.18)

        RowLayout {
            id: row
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.gridUnit
            anchors.rightMargin: Kirigami.Units.smallSpacing * 2
            spacing: Kirigami.Units.smallSpacing
        }
    }

    VirtualKeyboardLoader {
        id: inputPanel
        z: 1
        screenRoot: root
        mainStack: signIn
        mainBlock: signInPage
        passwordField: passwordBox
    }

    // The accounts at the bottom left; the keyboard layout, the on-screen keyboard, power and the
    // battery at the bottom right. Keep this in step with the lock screen's footer.
    RowLayout {
        id: footer
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            margins: Kirigami.Units.gridUnit
        }
        spacing: Kirigami.Units.smallSpacing

        Behavior on opacity {
            OpacityAnimator {
                duration: Kirigami.Units.longDuration
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignBottom
            spacing: Kirigami.Units.smallSpacing / 2

            Repeater {
                model: userModel
                delegate: FooterTile {
                    required property int index
                    required property var model
                    text: model.realName || model.name
                    avatarSource: root.photo(model.icon)
                    current: index === root.currentUser
                    onClicked: root.choose(index)
                }
            }
            FooterTile {
                text: i18ndc("plasma-desktop-sddm-theme", "@action:button For switching to a username and password prompt", "Other…").replace("…", "")
                iconName: "system-user-prompt"
                current: root.currentUser < 0
                onClicked: root.choose(-1)
            }
        }

        Item {
            Layout.fillWidth: true
        }

        KeyboardButton {
            id: keyboardButton
            Layout.alignment: Qt.AlignBottom
            onKeyboardLayoutChanged: passwordBox.forceActiveFocus()
        }

        PlasmaComponents3.ToolButton {
            Layout.alignment: Qt.AlignBottom
            display: PlasmaComponents3.AbstractButton.IconOnly
            text: i18ndc("plasma-desktop-sddm-theme", "Button to show/hide virtual keyboard", "Virtual Keyboard")
            icon.name: "preferences-desktop-accessibility"
            checkable: true
            checked: inputPanel.keyboardActive
            visible: inputPanel.status === Loader.Ready
            onClicked: {
                passwordBox.forceActiveFocus();
                inputPanel.showHide();
            }
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered
        }

        PlasmaComponents3.ToolButton {
            id: powerButton
            Layout.alignment: Qt.AlignBottom
            display: PlasmaComponents3.AbstractButton.IconOnly
            text: i18ndc("plasma-desktop-sddm-theme", "@action:button", "Shut Down")
            icon.name: "system-shutdown"
            onClicked: powerMenu.popup(powerButton, 0, -powerMenu.implicitHeight)
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered && !powerMenu.visible

            PlasmaComponents3.Menu {
                id: powerMenu
                PlasmaComponents3.MenuItem {
                    icon.name: "system-suspend"
                    text: i18ndc("plasma-desktop-sddm-theme", "@action:button Suspend to RAM", "Sleep")
                    enabled: sddm.canSuspend
                    onTriggered: sddm.suspend()
                }
                PlasmaComponents3.MenuItem {
                    icon.name: "system-reboot"
                    text: i18ndc("plasma-desktop-sddm-theme", "@action:button", "Restart")
                    enabled: sddm.canReboot
                    onTriggered: sddm.reboot()
                }
                PlasmaComponents3.MenuItem {
                    icon.name: "system-shutdown"
                    text: i18ndc("plasma-desktop-sddm-theme", "@action:button", "Shut Down")
                    enabled: sddm.canPowerOff
                    onTriggered: sddm.powerOff()
                }
            }
        }

        Battery {
            Layout.alignment: Qt.AlignBottom
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.notificationMessage = i18ndc("plasma-desktop-sddm-theme", "@info:status", "Login Failed");
            lockout.failed();
            passwordBox.text = "";
            passwordBox.forceActiveFocus();
            shake.start();
        }
        function onLoginSucceeded() {
            // SDDM ends the greeter soon after this; there's no telling whether a transition finishes.
            signIn.opacity = 0;
            footer.opacity = 0;
        }
    }

    onNotificationMessageChanged: {
        if (notificationMessage) {
            notificationResetTimer.start();
        }
    }

    Timer {
        id: notificationResetTimer
        interval: 3000
        onTriggered: root.notificationMessage = ""
    }
}
