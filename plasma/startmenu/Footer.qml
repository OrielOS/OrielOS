// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Layouts
import org.kde.coreaddons as KCoreAddons
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras

// The bar along the bottom: the account button on the left, the power button on the right.
PlasmaExtras.PlasmoidHeading {
    id: footer

    required property MenuState menu

    readonly property Item accountButton: accountButton
    readonly property Item powerButton: powerButton

    readonly property KCoreAddons.KUser user: KCoreAddons.KUser {}

    // The menu entries for these session actions, in this order, when the system offers them.
    // Hibernation is left out on purpose: OrielOS doesn't support it.
    function sessionEntries(actions): var {
        const model = footer.menu.systemModel;
        const idRole = model.KItemModels.KRoleNames.role("favoriteId");
        const entries = [];
        for (const action of actions) {
            for (let row = 0; row < model.count; ++row) {
                const index = model.index(row, 0);
                if (model.data(index, idRole) === action.id) {
                    entries.push({
                        text: action.text,
                        icon: String(model.data(index, Qt.DecorationRole) ?? ""),
                        handler: () => {
                            footer.menu.close();
                            model.trigger(row, "", null);
                        },
                    });
                    break;
                }
            }
        }
        return entries;
    }

    function openAccountMenu(fromKeyboard: bool) {
        const entries = [{
            text: KI18n.i18nc("@action:inmenu", "Account settings"),
            icon: "system-users",
            handler: () => {
                footer.menu.close();
                Qt.openUrlExternally("orielos-settings:your-info");
            },
        }];
        const session = footer.sessionEntries([
            { id: "lock-screen", text: KI18n.i18nc("@action:inmenu Lock the screen", "Lock") },
            { id: "switch-user", text: KI18n.i18nc("@action:inmenu", "Switch user") },
            { id: "logout", text: KI18n.i18nc("@action:inmenu End the session", "Sign out") },
        ]);
        if (session.length > 0) {
            entries.push({ separator: true });
        }
        accountMenu.showAbove(entries.concat(session), accountButton, fromKeyboard);
    }

    function closeMenus() {
        accountMenu.close();
        powerMenu.close();
    }

    function openPowerMenu(fromKeyboard: bool) {
        const entries = footer.sessionEntries([
            { id: "suspend", text: KI18n.i18nc("@action:inmenu Suspend to RAM", "Sleep") },
            { id: "reboot", text: KI18n.i18nc("@action:inmenu", "Restart") },
            { id: "shutdown", text: KI18n.i18nc("@action:inmenu", "Shut down") },
        ]);
        powerMenu.showAbove(entries, powerButton, fromKeyboard);
    }

    position: PC3.ToolBar.Footer

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        PC3.ToolButton {
            id: accountButton

            readonly property string name: footer.user.fullName.length > 0 ? footer.user.fullName : footer.user.loginName
            // Clicking the button while its menu is open closes the menu, so remember the state at
            // the press: the press itself closes the menu before the click.
            property bool menuWasOpen: false

            Layout.maximumWidth: footer.width / 2
            text: name
            down: pressed || accountMenu.opened
            Accessible.name: KI18n.i18nc("@action:button %1 is the user's name", "Account: %1", name)
            Accessible.role: Accessible.ButtonMenu

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                // Sill: the account's photo, or its initial on OrielOS's blue gradient.
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#9CC2FF" }
                        GradientStop { position: 1.0; color: "#3A66F0" }
                    }

                    PC3.Label {
                        anchors.centerIn: parent
                        visible: !photo.visible
                        text: accountButton.name.length > 0 ? accountButton.name.charAt(0).toUpperCase() : ""
                        color: "#FFFFFF"
                        font.weight: Font.Bold
                        font.pixelSize: 14
                    }

                    Kirigami.Icon {
                        id: photo
                        anchors.fill: parent
                        visible: footer.user.faceIconUrl.toString().length > 0
                        source: footer.user.faceIconUrl
                    }
                }

                PC3.Label {
                    Layout.fillWidth: true
                    text: accountButton.name
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }
            }

            onPressed: accountButton.menuWasOpen = accountMenu.visible || accountMenu.justClosed
            onClicked: {
                if (!accountButton.menuWasOpen) {
                    footer.openAccountMenu(false);
                }
            }
            Keys.onReturnPressed: footer.openAccountMenu(true)
            Keys.onEnterPressed: footer.openAccountMenu(true)
            Keys.onSpacePressed: footer.openAccountMenu(true)
            Keys.onTabPressed: footer.menu.cycleFocus(true)
            Keys.onBacktabPressed: footer.menu.cycleFocus(false)
        }

        Item {
            Layout.fillWidth: true
        }

        // Sill: shortcuts next to the power button (Downloads, Files, Settings).
        Repeater {
            model: [
                { text: KI18n.i18nc("@action:button", "Downloads"), icon: "folder-download", url: StandardPaths.writableLocation(StandardPaths.DownloadLocation) },
                { text: KI18n.i18nc("@action:button", "Files"), icon: "document-open-folder", url: StandardPaths.writableLocation(StandardPaths.HomeLocation) },
                { text: KI18n.i18nc("@action:button", "Settings"), icon: "orielos-settings-symbolic", app: "org.orielos.Settings.desktop" },
            ]

            delegate: PC3.ToolButton {
                required property var modelData

                text: modelData.text
                icon.name: modelData.icon
                display: PC3.AbstractButton.IconOnly
                Accessible.name: text
                PC3.ToolTip.text: text
                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                PC3.ToolTip.visible: hovered

                onClicked: {
                    if (modelData.app) {
                        const row = footer.menu.allAppsRow(modelData.app);
                        if (row >= 0) {
                            footer.menu.launchApp(row);
                        }
                    } else {
                        Qt.openUrlExternally(modelData.url);
                        footer.menu.close();
                    }
                }
                Keys.onTabPressed: footer.menu.cycleFocus(true)
                Keys.onBacktabPressed: footer.menu.cycleFocus(false)
            }
        }

        PC3.ToolButton {
            id: powerButton

            // As for the account button.
            property bool menuWasOpen: false

            text: KI18n.i18nc("@action:button", "Power")
            icon.name: "system-shutdown"
            display: PC3.AbstractButton.IconOnly
            down: pressed || powerMenu.opened
            Accessible.name: text
            Accessible.role: Accessible.ButtonMenu

            PC3.ToolTip.text: text
            PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
            PC3.ToolTip.visible: hovered && !powerMenu.opened

            onPressed: powerButton.menuWasOpen = powerMenu.visible || powerMenu.justClosed
            onClicked: {
                if (!powerButton.menuWasOpen) {
                    footer.openPowerMenu(false);
                }
            }
            Keys.onReturnPressed: footer.openPowerMenu(true)
            Keys.onEnterPressed: footer.openPowerMenu(true)
            Keys.onSpacePressed: footer.openPowerMenu(true)
            Keys.onTabPressed: footer.menu.cycleFocus(true)
            Keys.onBacktabPressed: footer.menu.cycleFocus(false)
        }
    }

    PopupMenu {
        id: accountMenu

        onFocusOwnerLost: footer.menu.focusSearch()
    }

    PopupMenu {
        id: powerMenu

        onFocusOwnerLost: footer.menu.focusSearch()
    }
}
