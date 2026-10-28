/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>
    SPDX-FileCopyrightText: 2026 OrielOS contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// OrielOS's lock screen, in Sill's style, from Plasma's lock screen layout (plasma-desktop 6.7.5,
// shells/org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml), whose unlocking logic it
// keeps. While the screen is idle, a large clock shows at the top over the wallpaper; a key press
// or a click slides it up and away and shows the sign-in (SignInBlock.qml) over the blurred
// wallpaper, with the account and Switch user at the bottom left and the keyboard layout, the
// on-screen keyboard, Sleep and the battery at the bottom right.

import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import org.kde.plasma.clock as PlasmaClock
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.workspace.components as PW
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker

import org.kde.plasma.private.sessions
import org.kde.breeze.components

Item {
    id: lockScreenUi

    // If we're using software rendering, draw outlines instead of shadows
    // See https://bugs.kde.org/show_bug.cgi?id=398317
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software

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
    }

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) { // if this is coming from the noninteractive authenticators
                return;
            }
            const msg = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Unlocking failed");
            lockScreenUi.handleMessage(msg);
            graceLockTimer.restart();
            notificationRemoveTimer.restart();
            rejectPasswordAnimation.start();
        }

        function onSucceeded() {
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

        function onPromptChanged(msg) {
            lockScreenUi.handleMessage(authenticator.prompt);
        }
        function onPromptForSecretChanged(msg) {
            mainBlock.showPassword = false;
            mainBlock.mainPasswordBox.forceActiveFocus();
        }
    }

    SessionManagement {
        id: sessionManagement
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
        property bool blockUI: containsMouse && (mainStack.depth > 1 || mainBlock.mainPasswordBox.text.length > 0 || inputPanel.keyboardActive)

        x: parent.x
        y: parent.y
        width: parent.width
        height: parent.height
        hoverEnabled: true
        cursorShape: uiVisible ? Qt.ArrowCursor : Qt.BlankCursor
        drag.filterChildren: true
        onPressed: uiVisible = true;
        onPositionChanged: {
            uiVisible = seenPositionChange;
            seenPositionChange = true;
        }
        onUiVisibleChanged: {
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
        onBlockUIChanged: {
            if (blockUI) {
                fadeoutTimer.running = false;
                uiVisible = true;
            } else {
                fadeoutTimer.restart();
            }
        }
        onExited: {
            uiVisible = false;
        }
        Keys.onEscapePressed: {
            // If the escape key is pressed, kscreenlocker will turn off the screen.
            // We do not want to show the password prompt in this case.
            if (uiVisible) {
                uiVisible = false;
                if (inputPanel.keyboardActive) {
                    inputPanel.showHide();
                }
                root.clearPassword();
            }
        }
        Keys.onPressed: event => {
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
        Timer {
            id: graceLockTimer
            interval: 3000
            onTriggered: {
                root.clearPassword();
                authenticator.startAuthenticating();
            }
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
            source: wallpaper
            mainStack: mainStack
            footer: footer
            // The fader would show the clock while unlocking; give it a stand-in and let the
            // OrielOS clock below fade itself.
            clock: faderClock
            alwaysShowClock: config.alwaysShowClock && !config.hideClockWhenIdle
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

                enabled: !graceLockTimer.running

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


                notificationMessage: {
                    const parts = [];
                    if (capsLockState.locked) {
                        parts.push(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Caps Lock is on"));
                    }
                    if (root.notification) {
                        parts.push(root.notification);
                    }
                    return parts.join(" • ");
                }

                onPasswordResult: password => {
                    authenticator.respond(password)
                }

                Loader {
                    Layout.fillWidth: true
                    Layout.preferredHeight: item ? item.implicitHeight : 0
                    active: config.showMediaControls
                    source: "MediaControls.qml"
                }
            }
        }

        VirtualKeyboardLoader {
            id: inputPanel

            z: 1

            screenRoot: lockScreenRoot
            mainStack: mainStack
            mainBlock: mainBlock
            passwordField: mainBlock.mainPasswordBox
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
                checked: inputPanel.keyboardActive
                onClicked: {
                    // Keep the password field focused, or the keyboard's keystrokes are lost.
                    mainBlock.mainPasswordBox.forceActiveFocus();
                    inputPanel.showHide();
                }
                visible: inputPanel.status === Loader.Ready
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
