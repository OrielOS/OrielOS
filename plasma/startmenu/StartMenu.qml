// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid

// The Start menu's popup: the search field, the home, all apps and search pages, and the footer.
FocusScope {
    id: root

    required property PlasmoidItem plasmoidItem

    readonly property MenuState menu: MenuState {
        plasmoidItem: root.plasmoidItem
        contextMenu: contextMenu
        query: searchField.text

        onQueryUpdateRequested: newQuery => {
            searchField.text = newQuery;
        }
        onFocusRequested: target => {
            switch (target) {
            case MenuState.Search:
                searchField.forceActiveFocus(Qt.BacktabFocusReason);
                break;
            case MenuState.Pinned:
                root.focusPinned();
                break;
            case MenuState.Recommended:
                root.focusRecommended();
                break;
            case MenuState.AllAppsList:
                root.focusAllAppsList();
                break;
            }
        }
        onShowingAllAppsChanged: {
            if (root.menu.showingAllApps) {
                allAppsPage.view.currentIndex = 0;
                allAppsPage.view.positionViewAtBeginning();
            }
        }
    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 36
    Layout.preferredWidth: Kirigami.Units.gridUnit * 36
    Layout.minimumHeight: Kirigami.Units.gridUnit * 40
    Layout.preferredHeight: Kirigami.Units.gridUnit * 40

    function focusPinned() {
        const grid = homePage.pinnedView;
        if (grid.count === 0) {
            root.focusRecommended();
            return;
        }
        if (grid.currentIndex < 0) {
            grid.currentIndex = 0;
        }
        grid.forceActiveFocus(Qt.TabFocusReason);
    }

    function focusRecommended() {
        const list = homePage.recommendedView;
        if (list.count === 0) {
            footer.accountButton.forceActiveFocus(Qt.TabFocusReason);
            return;
        }
        if (list.currentIndex < 0) {
            list.currentIndex = 0;
        }
        list.forceActiveFocus(Qt.TabFocusReason);
    }

    function focusAllAppsList() {
        const list = allAppsPage.view;
        if (list.count === 0) {
            return;
        }
        if (list.currentIndex < 0) {
            list.currentIndex = 0;
        }
        list.forceActiveFocus(Qt.TabFocusReason);
    }

    // The Tab order of the page that's showing.
    function focusChain(): var {
        const chain = [searchField];
        if (root.menu.searching) {
            if (searchPage.view.count > 0) {
                chain.push(searchPage.view);
            }
        } else if (root.menu.showingAllApps) {
            chain.push(allAppsPage.backButton);
            if (allAppsPage.view.count > 0) {
                chain.push(allAppsPage.view);
            }
        } else {
            chain.push(homePage.allAppsButton);
            if (homePage.pinnedView.count > 0) {
                chain.push(homePage.pinnedView);
            }
            if (homePage.recommendedView.count > 0) {
                chain.push(homePage.recommendedView);
            }
        }
        chain.push(footer.accountButton, footer.powerButton);
        return chain;
    }

    function moveFocus(forward: bool) {
        const chain = root.focusChain();
        let current = chain.findIndex(item => item.activeFocus);
        if (current < 0) {
            current = 0;
        }
        const next = chain[(current + (forward ? 1 : -1) + chain.length) % chain.length];
        if (next === homePage.pinnedView) {
            root.focusPinned();
        } else if (next === homePage.recommendedView) {
            root.focusRecommended();
        } else if (next === allAppsPage.view) {
            root.focusAllAppsList();
        } else {
            next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        }
    }

    // Each time the popup opens: an empty search on the home page.
    function prepare() {
        if (!root.menu.populated) {
            root.menu.populated = true;
            root.menu.rootModel.refresh();
        }
        searchField.clear();
        root.menu.showingAllApps = false;
        homePage.pinnedView.currentIndex = 0;
        homePage.recommendedView.currentIndex = 0;
        root.menu.syncFavorites();
        root.menu.rebuildRecommended();
        searchField.forceActiveFocus(Qt.ActiveWindowFocusReason);
    }

    Connections {
        target: root.plasmoidItem

        function onExpandedChanged() {
            if (root.plasmoidItem.expanded) {
                root.prepare();
            } else {
                contextMenu.close();
            }
        }
    }

    Component.onCompleted: {
        root.menu.syncFavorites();
        // The popup is created by its first opening, after expanded has changed.
        if (root.plasmoidItem.expanded) {
            root.prepare();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            // Step back one level at a time: the query, then the all apps page, then the menu.
            if (root.menu.searching) {
                searchField.clear();
                searchField.forceActiveFocus(Qt.OtherFocusReason);
            } else if (root.menu.showingAllApps) {
                root.menu.showHome();
                searchField.forceActiveFocus(Qt.OtherFocusReason);
            } else {
                root.menu.close();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            root.moveFocus(false);
            event.accepted = true;
        } else if (event.key === Qt.Key_Tab) {
            root.moveFocus(true);
            event.accepted = true;
        } else if (!searchField.activeFocus && event.text.trim().length > 0
                   && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                   && event.text.charCodeAt(0) >= 0x20 && event.text.charCodeAt(0) !== 0x7f) {
            // Typing anywhere in the menu searches.
            searchField.forceActiveFocus(Qt.ShortcutFocusReason);
            searchField.insert(searchField.cursorPosition, event.text);
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        PlasmaExtras.SearchField {
            id: searchField

            Layout.fillWidth: true
            focus: true
            placeholderText: KI18n.i18nc("@info:placeholder", "Search for apps, settings and files")
            Accessible.name: KI18n.i18nc("@info:accessible", "Search")

            onTextChanged: searchPage.resetCurrent()

            Keys.onPressed: event => {
                if (root.menu.isContextMenuKey(event)) {
                    if (root.menu.searching) {
                        searchPage.openCurrentMenu();
                    }
                    event.accepted = true;
                    return;
                }
                switch (event.key) {
                case Qt.Key_Up:
                    if (root.menu.searching) {
                        searchPage.moveCurrent(-1);
                        event.accepted = true;
                    }
                    break;
                case Qt.Key_Down:
                    if (root.menu.searching) {
                        searchPage.moveCurrent(1);
                    } else if (root.menu.showingAllApps) {
                        root.focusAllAppsList();
                    } else {
                        root.focusPinned();
                    }
                    event.accepted = true;
                    break;
                case Qt.Key_Tab:
                    // From an empty search field, Tab goes straight into the pinned apps.
                    if (!root.menu.searching && !root.menu.showingAllApps && !(event.modifiers & Qt.ShiftModifier)) {
                        root.focusPinned();
                        event.accepted = true;
                    }
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (root.menu.searching) {
                        searchPage.triggerCurrent();
                    }
                    event.accepted = true;
                    break;
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.menu.searching ? 2 : (root.menu.showingAllApps ? 1 : 0)

            HomePage {
                id: homePage
                menu: root.menu
            }

            AllApps {
                id: allAppsPage
                menu: root.menu
            }

            SearchResults {
                id: searchPage
                menu: root.menu
            }
        }

        Footer {
            id: footer
            Layout.fillWidth: true
            menu: root.menu
        }
    }

    PopupMenu {
        id: contextMenu
    }
}
