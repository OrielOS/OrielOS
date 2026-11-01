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
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

// The bar along the bottom: the account button on the left, the power button on the right.
PlasmaExtras.PlasmoidHeading {
    id: footer

    required property MenuState menu

    readonly property Item accountButton: accountButton
    readonly property Item powerButton: powerButton

    readonly property KCoreAddons.KUser user: KCoreAddons.KUser {}

    // Whether an update is waiting: the next restart or shut down installs it, so the power menu
    // says so, as Windows' "Update and restart" does. Checked each time Start opens.
    property bool updateWaiting: false

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
                            // Shift + Restart opens the boot menu, with its recovery options, next.
                            if (action.id === "reboot" && Plasmoid.shiftHeld()) { // qmllint disable missing-property
                                Plasmoid.showBootMenuNextStart(); // qmllint disable missing-property
                            }
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
            { id: "reboot", text: footer.updateWaiting ? KI18n.i18nc("@action:inmenu Restart, installing the waiting update", "Update and restart")
                : KI18n.i18nc("@action:inmenu", "Restart") },
            { id: "shutdown", text: footer.updateWaiting ? KI18n.i18nc("@action:inmenu Shut down, installing the waiting update", "Update and shut down")
                : KI18n.i18nc("@action:inmenu", "Shut down") },
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

        // Shortcuts next to the power button, those chosen in Settings' Start page (Sill shows
        // Downloads, Files and Settings), with Settings nearest the power button as in Windows.
        Repeater {
            model: {
                const shortcuts = {
                    settings: { text: KI18n.i18nc("@action:button", "Settings"), icon: "orielos-settings-symbolic", app: "org.orielos.Settings.desktop" },
                    files: { text: KI18n.i18nc("@action:button", "Files"), icon: "document-open-folder", url: StandardPaths.writableLocation(StandardPaths.HomeLocation) },
                    documents: { text: KI18n.i18nc("@action:button", "Documents"), icon: "folder-documents", url: StandardPaths.writableLocation(StandardPaths.DocumentsLocation) },
                    downloads: { text: KI18n.i18nc("@action:button", "Downloads"), icon: "folder-download", url: StandardPaths.writableLocation(StandardPaths.DownloadLocation) },
                    music: { text: KI18n.i18nc("@action:button", "Music"), icon: "folder-music", url: StandardPaths.writableLocation(StandardPaths.MusicLocation) },
                    pictures: { text: KI18n.i18nc("@action:button", "Pictures"), icon: "folder-pictures", url: StandardPaths.writableLocation(StandardPaths.PicturesLocation) },
                    videos: { text: KI18n.i18nc("@action:button", "Videos"), icon: "folder-videos", url: StandardPaths.writableLocation(StandardPaths.MoviesLocation) },
                    network: { text: KI18n.i18nc("@action:button", "Network"), icon: "folder-network", url: "remote:/" },
                    personal: { text: KI18n.i18nc("@action:button The home folder", "Personal folder"), icon: "user-home", url: StandardPaths.writableLocation(StandardPaths.HomeLocation) },
                };
                const order = ["personal", "network", "videos", "pictures", "music", "downloads", "documents", "files", "settings"];
                return order.filter(id => footer.menu.folders.includes(id)).map(id => shortcuts[id]);
            }

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

            PC3.ToolTip.text: footer.updateWaiting ? KI18n.i18nc("@info:tooltip", "Power (an update is waiting)") : text
            PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
            PC3.ToolTip.visible: hovered && !powerMenu.opened

            // The orange dot that says an update waits for the next restart or shut down.
            Rectangle {
                visible: footer.updateWaiting
                width: Kirigami.Units.smallSpacing * 2
                height: width
                radius: width / 2
                color: "#f7a440"
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Kirigami.Units.smallSpacing
            }

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

    // An update downloaded in the background waits as a staged deployment until the next start.
    P5Support.DataSource {
        id: updateCheck

        readonly property string command: "test -e /run/ostree/staged-deployment && echo waiting"

        engine: "executable"
        onNewData: (source, data) => {
            footer.updateWaiting = String(data.stdout).trim() === "waiting";
            disconnectSource(source);
        }
    }

    Connections {
        target: footer.menu.plasmoidItem

        function onExpandedChanged() {
            if (footer.menu.plasmoidItem.expanded) {
                updateCheck.connectSource(updateCheck.command);
            }
        }
    }

    Component.onCompleted: updateCheck.connectSource(updateCheck.command)

    PopupMenu {
        id: powerMenu

        onFocusOwnerLost: footer.menu.focusSearch()
    }
}
