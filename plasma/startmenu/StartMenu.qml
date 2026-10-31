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
    // Start was opened to search (Win+S or the taskbar's Search button): it shows the search home.
    property bool openForSearch: false

    // The search home is showing for the request above.
    signal searchOpened()

    // Sill's roomy inset around the search field and the pages, beyond the popup's own padding.
    readonly property int inset: 22

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
            }
        }
        onFocusCycleRequested: forward => root.moveFocus(forward)
        onShowingMoreChanged: {
            if (root.menu.showingMore) {
                morePage.view.currentIndex = 0;
                morePage.view.positionViewAtBeginning();
                Qt.callLater(root.focusAfterPageSwitch);
            } else if (!root.menu.showingAllApps) {
                root.focusAfterPageSwitch();
            }
        }
        onShowingAllAppsChanged: {
            if (root.menu.showingAllApps) {
                allAppsPage.reset();
                allAppsPage.view.currentIndex = 0;
                allAppsPage.view.positionViewAtBeginning();
                // The page shows once the stack has laid itself out again.
                Qt.callLater(root.focusAfterPageSwitch);
            } else {
                root.focusAfterPageSwitch();
            }
        }
        // Only the search field starts and ends a search, and it stays where the focus belongs
        // when the page under it changes.
        onSearchingChanged: {
            if (!searchField.activeFocus) {
                searchField.forceActiveFocus(Qt.OtherFocusReason);
            }
        }
    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 34
    Layout.preferredWidth: Kirigami.Units.gridUnit * 34
    Layout.minimumHeight: Kirigami.Units.gridUnit * 38
    Layout.preferredHeight: Kirigami.Units.gridUnit * 38

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
            allAppsPage.backButton.forceActiveFocus(Qt.TabFocusReason);
            return;
        }
        if (list.currentIndex < 0) {
            list.currentIndex = 0;
        }
        list.forceActiveFocus(Qt.TabFocusReason);
    }

    function focusSearchHome() {
        const recent = searchHomePage.recentView;
        const topApps = searchHomePage.topAppsView;
        if (recent.count > 0) {
            if (recent.currentIndex < 0) {
                recent.currentIndex = 0;
            }
            recent.forceActiveFocus(Qt.TabFocusReason);
        } else if (searchHomePage.topAppsShown > 0) {
            if (topApps.currentIndex < 0) {
                topApps.currentIndex = 0;
            }
            topApps.forceActiveFocus(Qt.TabFocusReason);
        }
    }

    function focusMoreList() {
        const list = morePage.view;
        if (list.count === 0) {
            morePage.backButton.forceActiveFocus(Qt.TabFocusReason);
            return;
        }
        if (list.currentIndex < 0) {
            list.currentIndex = 0;
        }
        list.forceActiveFocus(Qt.TabFocusReason);
    }

    // The focus never stays on the page that was hidden: the all apps page starts in its list,
    // and the home page in the search field.
    function focusAfterPageSwitch() {
        if (root.menu.searching) {
            return;
        }
        if (root.menu.showingAllApps) {
            root.focusAllAppsList();
        } else if (root.menu.showingMore) {
            root.focusMoreList();
        } else {
            searchField.forceActiveFocus(Qt.OtherFocusReason);
        }
    }

    // The Tab order of the page that's showing.
    function focusChain(): var {
        const chain = [searchField];
        if (root.menu.searching) {
            if (searchPage.view.count > 0) {
                chain.push(searchPage.view);
            }
        } else if (root.menu.showingAllApps) {
            chain.push(allAppsPage.viewButton, allAppsPage.backButton);
            if (allAppsPage.view.count > 0) {
                chain.push(allAppsPage.view);
            }
        } else if (root.menu.showingMore) {
            chain.push(morePage.backButton);
            if (morePage.view.count > 0) {
                chain.push(morePage.view);
            }
        } else if (root.menu.searchHome) {
            if (searchHomePage.recentView.count > 0) {
                chain.push(searchHomePage.clearButton, searchHomePage.recentView);
            }
            if (searchHomePage.topAppsShown > 0) {
                chain.push(searchHomePage.topAppsView);
            }
        } else {
            chain.push(homePage.allAppsButton);
            if (homePage.pinnedView.count > 0) {
                chain.push(homePage.pinnedView);
            }
            chain.push(homePage.moreButton);
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
        } else if (next === morePage.view) {
            root.focusMoreList();
        } else {
            next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        }
    }

    // Each time the popup opens: an empty search on the home page.
    function prepare() {
        if (!root.menu.populated) {
            root.menu.populated = true;
            root.menu.rootModel.refresh();
            root.menu.categoriesRootModel.refresh();
        }
        searchField.clear();
        root.menu.showHome();
        homePage.reset();
        homePage.pinnedView.currentIndex = 0;
        homePage.recommendedView.currentIndex = 0;
        root.menu.syncFavorites();
        root.menu.rebuildRecommended();
        searchField.forceActiveFocus(Qt.ActiveWindowFocusReason);
        if (root.openForSearch) {
            root.showSearchHome();
        }
    }

    // The search home, with the search field ready for typing.
    function showSearchHome() {
        searchField.clear();
        root.menu.showSearchHome();
        searchHomePage.recentView.currentIndex = 0;
        searchHomePage.topAppsView.currentIndex = 0;
        searchField.forceActiveFocus(Qt.ShortcutFocusReason);
        root.searchOpened();
    }

    // Asked to search while already open.
    onOpenForSearchChanged: {
        if (root.openForSearch && root.plasmoidItem.expanded) {
            root.showSearchHome();
        }
    }

    Connections {
        target: root.plasmoidItem

        function onExpandedChanged() {
            if (root.plasmoidItem.expanded) {
                root.prepare();
            } else {
                contextMenu.close();
                footer.closeMenus();
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
            // Step back one level at a time: the query, then the all apps, More or search home
            // page, then the menu.
            if (root.menu.searching) {
                searchField.clear();
                searchField.forceActiveFocus(Qt.OtherFocusReason);
            } else if (root.menu.showingAllApps || root.menu.showingMore || root.menu.searchHome) {
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
            Layout.topMargin: root.inset - Kirigami.Units.smallSpacing
            Layout.leftMargin: root.inset
            Layout.rightMargin: root.inset
            Layout.bottomMargin: root.inset
            focus: true
            placeholderText: KI18n.i18nc("@info:placeholder", "Search for apps, settings and files")
            Accessible.name: KI18n.i18nc("@info:accessible", "Search")

            onTextChanged: searchPage.resetCurrent()
            // Clicking in the empty field shows the search home, as Windows' Start does.
            onPressed: {
                if (!root.menu.searching && !root.menu.searchHome) {
                    root.menu.showSearchHome();
                }
            }

            // The field takes Tab itself, so the root's handler never sees it.
            Keys.onTabPressed: root.moveFocus(true)
            Keys.onBacktabPressed: root.moveFocus(false)
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
                    } else if (root.menu.showingMore) {
                        root.focusMoreList();
                    } else if (root.menu.searchHome) {
                        root.focusSearchHome();
                    } else {
                        root.focusPinned();
                    }
                    event.accepted = true;
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
            Layout.leftMargin: root.inset
            Layout.rightMargin: root.inset
            currentIndex: {
                if (root.menu.searching) {
                    return 2;
                }
                if (root.menu.showingAllApps) {
                    return 1;
                }
                if (root.menu.showingMore) {
                    return 3;
                }
                return root.menu.searchHome ? 4 : 0;
            }

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

            MorePage {
                id: morePage
                menu: root.menu
            }

            SearchHome {
                id: searchHomePage
                menu: root.menu
            }
        }

        Footer {
            id: footer
            Layout.fillWidth: true
            leftPadding: root.inset
            rightPadding: root.inset
            topPadding: Kirigami.Units.largeSpacing
            bottomPadding: Kirigami.Units.largeSpacing
            menu: root.menu
        }
    }

    PopupMenu {
        id: contextMenu

        onFocusOwnerLost: searchField.forceActiveFocus(Qt.PopupFocusReason)
    }
}
