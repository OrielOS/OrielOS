/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>
    SPDX-FileCopyrightText: 2026 Kristen McWilliam <kristen@kde.org>
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// OrielOS's lock screen, in Sill's style, from Plasma's lock screen layout (plasma-desktop 6.8.2,
// shells/org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml), whose unlocking logic it
// keeps. While the screen is idle, a large clock shows at the top over the wallpaper, with the next
// calendar item (LockDetail.qml) above the bottom and the quick status (LockStatus.qml) at the bottom
// right; a key press or a click slides it up and away and shows the sign-in (SignInBlock.qml) over the blurred
// wallpaper, with the account and Switch user at the bottom left and the keyboard layout, the
// on-screen keyboard, Sleep and the battery at the bottom right.

pragma ComponentBehavior: Bound

import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import org.kde.plasma.clock as PlasmaClock
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.accessibility
import org.kde.plasma.workspace.components as PW
import org.kde.plasma.workspace.keyboardlayout as Keyboards
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker
import org.kde.ki18n

import org.kde.plasma.private.sessions
import org.kde.breeze.components

Item {
    id: lockScreenUi

    // If we're using software rendering, draw outlines instead of shadows
    // See https://bugs.kde.org/show_bug.cgi?id=398317
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    // Whether we expect a given authenticator to prompt for a credential at all.
    // This is a shortcut around the NoPasswordUnlock.qml screen when dealing with prompt-less authenticators.
    property bool expectingPrompt: false // this is set for real when an authenticator is selected
    // <!* Whether we are expected to visualize the prompt message for the authenticator *>
    property bool showPrompt: false // this is set for real when an authenticator is selected

    // The colour scheme decides which wallpaper image shows: Daybreak (light) or Nightfall
    // (dark). The rest of the lock screen uses the complementary colours, so read the window
    // colours here to tell them apart.
    Item {
        id: schemeProbe
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
    }
    readonly property bool lightScheme: Math.max(schemeProbe.Kirigami.Theme.backgroundColor.r,
        schemeProbe.Kirigami.Theme.backgroundColor.g, schemeProbe.Kirigami.Theme.backgroundColor.b) > 0.5
    readonly property color clockColor: lightScheme ? "#121A2E" : "#FFFFFF"

    function handleMessage(msg) {
        if (!root.notification) {
            root.notification += msg;
        } else if (root.notification.includes(msg)) {
            root.notificationRepeated();
        } else {
            root.notification += "\n" + msg
        }
        // A message brings up the sign-in, unless Ctrl+Alt+Delete has to come first.
        if (!lockScreenRoot.needsCtrlAltDel) {
            lockScreenRoot.uiVisible = true
        }
    }

    property string pendingPassword

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) { // if this is coming from the noninteractive authenticators
                return;
            }
            const msg = mainBlock.pinMode
                ? i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "The PIN is incorrect. Try again.")
                : i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Unlocking failed");
            lockout.failed();
            lockScreenUi.handleMessage(msg);
            root.clearPassword();
            authenticator.startAuthenticating();
            notificationRemoveTimer.restart();
            rejectPasswordAnimation.start();
        }

        function onSucceeded() {
            // This is important. It stops the all pending authentication processes, preventing timeouts etc.
            authenticator.stopAuthenticating()

            if (!lockScreenUi.expectingPrompt) {
                Qt.quit()
            }
            if (authenticator.hadPrompt) {
                Qt.quit();
            } else {
                mainStack.replace(null, Qt.resolvedUrl("NoPasswordUnlock.qml"),
                    {
                        userListModel: users
                    },
                    StackView.Immediate,
                );
                mainStack.forceActiveFocus();
            }
        }

        function onInfoMessageChanged() {
            lockScreenUi.handleMessage(authenticator.infoMessage);
        }

        function onErrorMessageChanged() {
            lockScreenUi.handleMessage(authenticator.errorMessage);
        }

        function onPromptChanged() {
            lockScreenUi.handleMessage(authenticator.prompt);
        }
        function onPromptForSecretChanged() {
            mainBlock.showPassword = false;
            mainBlock.mainPasswordBox.forceActiveFocus();
            if (lockScreenUi.showPrompt) {
                lockScreenUi.handleMessage(authenticator.promptForSecret);
            }
        }
    }

    SessionManagement {
        id: sessionManagement
    }

    AccessibilityStatus {
        id: accessibilityStatus
    }

    Lockout {
        id: lockout
    }

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    Connections {
        target: sessionManagement
        function onAboutToSuspend() {
            root.clearPassword();
        }
    }

    RejectPasswordAnimation {
        id: rejectPasswordAnimation
        target: mainBlock
    }

    MouseArea {
        id: lockScreenRoot

        property bool uiVisible: false
        property bool seenPositionChange: false
        // With "press Ctrl+Alt+Delete to sign in" on, only that brings up the sign-in; the keys
        // can't be faked by an app, so whoever types the password is talking to the real screen.
        readonly property bool needsCtrlAltDel: config.requireCtrlAltDel && !ctrlAltDelPressed
        property bool ctrlAltDelPressed: false
        property bool blockUI: containsMouse && (mainStack.depth > 1 || mainBlock.mainPasswordBox.text.length > 0 || Keyboards.KWinVirtualKeyboard.visible)

        x: parent.x
        y: parent.y
        width: parent.width
        height: parent.height
        hoverEnabled: true
        cursorShape: uiVisible ? Qt.ArrowCursor : Qt.BlankCursor
        drag.filterChildren: true
        onPressed: uiVisible = !needsCtrlAltDel;
        onPositionChanged: {
            uiVisible = seenPositionChange && !needsCtrlAltDel;
            seenPositionChange = true;
        }
        onUiVisibleChanged: {
            if (!uiVisible) {
                ctrlAltDelPressed = false;
            }
            if (uiVisible) {
                Window.window.requestActivate();
            }

            if (blockUI) {
                fadeoutTimer.running = false;
            } else if (uiVisible) {
                fadeoutTimer.restart();
            }
            authenticator.startAuthenticating();
        }

        Timer { // heart beat keeping the backend active for as long as we are in visible state
            interval: 1000
            running: !authenticator.unlocked && parent.uiVisible
            repeat: true
            onTriggered: authenticator.startAuthenticating()
        }

        onBlockUIChanged: {
            if (blockUI) {
                fadeoutTimer.running = false;
                uiVisible = true;
            } else {
                fadeoutTimer.restart();
            }
        }
        ScreenLocker.ActiveScreenMonitor {
            id: activeScreenMonitor
            lockscreenState: ScreenLocker.LockscreenState
            window: lockScreenRoot.Window.window
            onActiveChanged: {
                if(!active) {
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Keys.onEscapePressed: {
            // If the escape key is pressed, kscreenlocker will turn off the screen.
            // We do not want to show the password prompt in this case.
            if (uiVisible) {
                uiVisible = false;
                if (Keyboards.KWinVirtualKeyboard.visible) {
                    Keyboards.KWinVirtualKeyboard.active = false;
                }
                root.clearPassword();
            }
        }
        Keys.onPressed: event => {
            if (needsCtrlAltDel) {
                if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.AltModifier)) {
                    ctrlAltDelPressed = true;
                    uiVisible = true;
                }
                event.accepted = true;
                return;
            }
            uiVisible = true;
            event.accepted = false;
        }
        Timer {
            id: fadeoutTimer
            interval: 10000
            onTriggered: {
                if (!lockScreenRoot.blockUI) {
                    mainBlock.mainPasswordBox.showPassword = false;
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Timer {
            id: notificationRemoveTimer
            interval: 3000
            onTriggered: root.notification = ""
        }

        PropertyAnimation {
            id: launchAnimation
            target: lockScreenRoot
            property: "opacity"
            from: 0
            to: 1
            duration: Kirigami.Units.veryLongDuration * 2
        }

        Component.onCompleted: launchAnimation.start();

        WallpaperFader {
            anchors.fill: parent
            state: lockScreenRoot.uiVisible ? "on" : "off"
            mainStack: mainStack
            footer: footer
            // The fader would show the clock while unlocking; give it a stand-in and let the
            // OrielOS clock below fade itself.
            clock: faderClock
            alwaysShowClock: config.alwaysShowClock && !config.hideClockWhenIdle

            Component.onCompleted: source = wallpaper
        }

        Item {
            id: faderClock
            property Item shadow: Item {}
            visible: false
        }

        DropShadow {
            id: clockShadow
            anchors.fill: clock
            source: clock
            // Ink on the light wallpaper needs no shadow; white on the dark one does.
            visible: !lockScreenUi.softwareRendering && !lockScreenUi.lightScheme && clock.visible
            radius: 7
            verticalOffset: 0.8
            samples: 15
            spread: 0.2
            color : Qt.rgba(0, 0, 0, 0.7)
            opacity: clock.opacity
        }

        // The time and date, large at the top centre while the screen is idle, as long as the user
        // keeps Plasma's "show clock" lock screen setting on. They slide up and fade as the
        // sign-in shows.
        ColumnLayout {
            id: clock
            readonly property bool showWhenIdle: config.alwaysShowClock && !config.hideClockWhenIdle
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(lockScreenRoot.height * 0.02)
            spacing: 0
            opacity: !lockScreenRoot.uiVisible && showWhenIdle ? 1 : 0
            visible: opacity > 0
            transform: Translate {
                y: lockScreenRoot.uiVisible ? -(clock.y + clock.height) : 0
                Behavior on y {
                    NumberAnimation {
                        duration: Kirigami.Units.veryLongDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }
            Behavior on opacity {
                OpacityAnimator {
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.InOutQuad
                }
            }

            PlasmaComponents3.Label {
                text: Qt.formatTime(timeSource.dateTime, Qt.locale(), Locale.ShortFormat)
                textFormat: Text.PlainText
                color: lockScreenUi.clockColor
                style: lockScreenUi.softwareRendering && !lockScreenUi.lightScheme ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.6)
                font.family: "Noto Sans Display"
                font.pixelSize: Math.round(Math.min(lockScreenRoot.height * 0.105, lockScreenRoot.width * 0.075))
                font.weight: Font.DemiBold
                font.letterSpacing: -2.0
                renderType: Text.QtRendering
                Layout.alignment: Qt.AlignHCenter
            }
            PlasmaComponents3.Label {
                text: Qt.locale().toString(timeSource.dateTime, "dddd d MMMM")
                textFormat: Text.PlainText
                color: lockScreenUi.clockColor
                style: lockScreenUi.softwareRendering && !lockScreenUi.lightScheme ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.6)
                font.pixelSize: Math.round(Math.min(lockScreenRoot.height * 0.025, 26))
                font.weight: Font.Medium
                Layout.alignment: Qt.AlignHCenter
            }

            PlasmaClock.Clock {
                id: timeSource
                trackSeconds: Qt.locale().timeFormat(Locale.ShortFormat).includes("s")
            }
        }

        // New notifications by app, the network and the battery at the bottom right while the
        // screen is idle; the sign-in's footer takes their place when it shows.
        PlasmaComponents3.Label {
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: 180
            }
            visible: config.requireCtrlAltDel && !lockScreenRoot.uiVisible
            text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "Press Ctrl+Alt+Delete to unlock")
            textFormat: Text.PlainText
            color: lockScreenUi.clockColor
            font.pixelSize: 18
        }

        LockDetail {
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: 120
            }
            textColor: "#FFFFFF"
            calendars: config.detailedStatusCalendars
            opacity: lockScreenRoot.uiVisible ? 0 : 1
            visible: text !== "" && opacity > 0
            Behavior on opacity {
                OpacityAnimator {
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.InOutQuad
                }
            }
        }

        LockStatus {
            anchors {
                right: parent.right
                bottom: parent.bottom
                rightMargin: 28
                bottomMargin: 26
            }
            color: lockScreenUi.clockColor
            opacity: lockScreenRoot.uiVisible ? 0 : 1
            visible: opacity > 0
            Behavior on opacity {
                OpacityAnimator {
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.InOutQuad
                }
            }
        }

        ListModel {
            id: users

            Component.onCompleted: {
                users.append({
                    name: kscreenlocker_userName,
                    realName: kscreenlocker_userName,
                    icon: kscreenlocker_userImage !== ""
                          ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/")
                          : "",
                })
            }
        }

        Connections {
            target: authenticator
            function onPamTimeoutChanged(): void {
                if (!authenticator.pamTimeout && lockScreenUi.pendingPassword.length > 0) {
                    authenticator.respond(lockScreenUi.pendingPassword);
                    lockScreenUi.pendingPassword = "";
                    mainBlock.enabled = true;
                }
            }
        }

        StackView {
            id: mainStack
            anchors {
                left: parent.left
                right: parent.right
            }
            height: lockScreenRoot.height + Kirigami.Units.gridUnit * 3
            focus: true //StackView is an implicit focus scope, so we need to give this focus so the item inside will have it

            // this isn't implicit, otherwise items still get processed for the scenegraph
            visible: opacity > 0

            initialItem: SignInBlock {
                id: mainBlock
                lockScreenUiVisible: lockScreenRoot.uiVisible

                // The sign-in rises a little as it fades in.
                transform: Translate {
                    y: lockScreenRoot.uiVisible ? 0 : Kirigami.Units.gridUnit * 2
                    Behavior on y {
                        NumberAnimation {
                            duration: Kirigami.Units.veryLongDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                StackView.onStatusChanged: {
                    // prepare for presenting again to the user
                    if (StackView.status === StackView.Activating) {
                        mainPasswordBox.clear();
                        mainPasswordBox.focus = true;
                        root.notification = "";
                    }
                }
                userListModel: users
                challenge: lockout.phrase
                waitSeconds: lockout.secondsLeft

                notificationMessage: {
                    const parts = [];
                    if (lockout.phrase !== "") {
                        parts.push(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Too many wrong passwords. Type the characters shown to carry on."));
                    } else if (lockout.secondsLeft > 0) {
                        parts.push(i18ndcp("plasma_shell_org.kde.plasma.desktop", "@info:status", "Try again in %1 second.", "Try again in %1 seconds.", lockout.secondsLeft));
                    }
                    if (capsLockState.locked) {
                        parts.push(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Caps Lock is on"));
                    }
                    if (accessibilityStatus.slowKeysEnabled) {
                        parts.push(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Slow Keys are enabled"));
                    }
                    if (root.notification) {
                        parts.push(root.notification);
                    }
                    return parts.join(" • ");
                }

                onPasswordResult: password => {
                    if (authenticator.pamTimeout) {
                        lockScreenUi.pendingPassword = password
                        mainBlock.enabled = false
                    } else {
                        authenticator.respond(password)
                    }
                }
                onChallengeResult: text => {
                    if (!lockout.answer(text)) {
                        rejectPasswordAnimation.start();
                    }
                    root.notification = "";
                    root.clearPassword();
                }

                // A button for each way in (password, fingerprint, smart card) when there's more
                // than one, as Plasma 6.8's lock screen has; the screen locker listens for one at a time.
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    visible: authenticationTypeRepeater.count > 1

                    Repeater {
                        id: authenticationTypeRepeater
                        model: ScreenLocker.AuthenticatorModel

                        delegate: PlasmaComponents3.Button {
                            required property int type
                            required property string iconName
                            required property bool passwordField
                            required property bool expectingPrompt
                            required property string tooltip
                            required property bool showPrompt
                            required property bool functional

                            onFunctionalChanged: {
                                if (functional) {
                                    return
                                }
                                root.notification = ""
                                mainBlock.passwordInputVisible = false
                                lockScreenUi.handleMessage(KI18n.i18ndc(
                                    "plasma_shell_org.kde.plasma.desktop",
                                    "@info:status",
                                    "This authentication method is not functioning correctly. Please try another method, and check your system configuration."))
                            }

                            // Defunct methods are disabled; the handler above says why.
                            enabled: functional
                            display: PlasmaComponents3.AbstractButton.IconOnly
                            text: tooltip
                            icon.name: iconName
                            icon.color: functional ? undefined : Kirigami.Theme.negativeTextColor
                            checkable: true
                            checked: authenticator.authenticator === type
                            onClicked: {
                                authenticator.authenticator = type
                                root.notification = ""
                                mainBlock.passwordInputVisible = passwordField
                                lockScreenUi.expectingPrompt = expectingPrompt
                                lockScreenUi.showPrompt = showPrompt
                            }

                            PlasmaComponents3.ToolTip.text: tooltip
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                            PlasmaComponents3.ToolTip.visible: hovered

                            Component.onCompleted: {
                                if (checked) {
                                    clicked()
                                }
                            }
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    Layout.preferredHeight: item ? item.implicitHeight : 0
                    active: config.showMediaControls
                    source: "MediaControls.qml"
                }
            }
        }

        Loader {
            z: 2
            active: root.viewVisible
            source: "LockOsd.qml"
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Kirigami.Units.gridUnit
            }
        }

        // The account and Switch user at the bottom left; the keyboard layout, the on-screen
        // keyboard, Sleep and the battery at the bottom right. WallpaperFader shows the footer
        // with the sign-in. Note for contributors: keep this in step with the sign-in screen's
        // footer (image/sddm/orielos/Main.qml).
        RowLayout {
            id: footer
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: Kirigami.Units.gridUnit
            }
            spacing: Kirigami.Units.smallSpacing

            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing / 2

                FooterTile {
                    text: users.count > 0 ? users.get(0).realName : ""
                    avatarSource: users.count > 0 ? users.get(0).icon : ""
                    current: true
                }
                FooterTile {
                    text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "Switch &User").replace("&", "")
                    iconName: "system-switch-user"
                    visible: sessionManagement.canSwitchUser
                    onClicked: sessionManagement.switchUser()
                }
            }

            Item {
                Layout.fillWidth: true
            }

            PlasmaComponents3.ToolButton {
                id: keyboardButton
                Layout.alignment: Qt.AlignBottom
                focusPolicy: Qt.TabFocus
                Accessible.description: i18ndc("plasma_shell_org.kde.plasma.desktop", "Button to change keyboard layout", "Switch layout")
                PW.KeyboardLayoutSwitcher {
                    id: keyboardLayoutSwitcher
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                }
                text: keyboardLayoutSwitcher.layoutNames.shortName.toUpperCase()
                onClicked: keyboardLayoutSwitcher.keyboardLayout.switchToNextLayout()
                visible: keyboardLayoutSwitcher.hasMultipleKeyboardLayouts
            }

            PlasmaComponents3.ToolButton {
                id: virtualKeyboardButton
                Layout.alignment: Qt.AlignBottom
                focusPolicy: Qt.TabFocus
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: i18ndc("plasma_shell_org.kde.plasma.desktop", "Button to show/hide virtual keyboard", "Virtual Keyboard")
                icon.name: "preferences-desktop-accessibility"
                checkable: true
                checked: Keyboards.KWinVirtualKeyboard.visible
                onClicked: {
                    if (Keyboards.KWinVirtualKeyboard.visible) {
                        Keyboards.KWinVirtualKeyboard.active = false;
                    } else {
                        // Keep the password field focused, or the keyboard's keystrokes are lost.
                        mainBlock.mainPasswordBox.forceActiveFocus();
                        Keyboards.KWinVirtualKeyboard.forceActivate();
                    }
                }
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
            }

            PlasmaComponents3.ToolButton {
                id: powerButton
                Layout.alignment: Qt.AlignBottom
                focusPolicy: Qt.TabFocus
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "Slee&p").replace("&", "")
                icon.name: "system-suspend"
                onClicked: sessionManagement.suspend()
                visible: sessionManagement.canSuspend
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
            }

            Battery {
                Layout.alignment: Qt.AlignBottom
            }
        }
    }
}
