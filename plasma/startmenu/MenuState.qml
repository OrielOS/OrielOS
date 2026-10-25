// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.ki18n
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker

// The Start menu's models and the actions its pages share: pinning, launching, context menus
// and moving the keyboard focus between the pages' parts.
QtObject {
    id: state

    enum FocusTarget {
        Search,
        Pinned,
        Recommended
    }

    required property PlasmoidItem plasmoidItem
    required property PopupMenu contextMenu

    property string query: ""
    readonly property bool searching: query.length > 0
    property bool showingAllApps: false

    readonly property int pinnedColumns: 6
    readonly property int pinnedRows: 3
    readonly property int recommendedLimit: 6

    // The root model is filled the first time the menu opens, as Kickoff does.
    property bool populated: false

    // The page asks for the focus to move to one of its parts.
    signal focusRequested(int target)
    // A runner rewrote the search query.
    signal queryUpdateRequested(string newQuery)
    // Tab or Shift+Tab was pressed on one of the page's parts.
    signal focusCycleRequested(bool forward)

    //BEGIN Models
    readonly property Kicker.RootModel rootModel: Kicker.RootModel {
        appletInterface: state.plasmoidItem
        autoPopulate: false
        flat: true
        sorted: true
        showAllApps: true
        showAllAppsCategorized: false
        showTopLevelItems: false
        showRecentApps: false
        showRecentDocs: false
        showRecentFolders: false
        showPowerSession: false
        showFavoritesPlaceholder: false
        showSeparators: false
        highlightNewlyInstalledApps: true

        // Apps were installed or removed: a pinned app the favourites model dropped may now exist.
        onRefreshed: {
            state.findAllAppsModel();
            state.syncFavorites();
            state.rebuildRecommended();
        }
    }

    // Every app, alphabetically. modelForRow() makes no binding, so it's looked up on refresh.
    property Kicker.AppsModel allAppsModel: null

    // The pinned apps. Plasmoid.configuration.favorites is the only record of them: the model
    // drops apps that aren't installed (yet) from its own list, so it is never written back.
    readonly property Kicker.SimpleFavoritesModel favoritesModel: Kicker.SimpleFavoritesModel {}
    readonly property var pinnedIds: Array.from(Plasmoid.configuration.favorites ?? []).map(id => state.normaliseId(String(id)))
    onPinnedIdsChanged: state.syncFavorites()

    // Apps installed in the last few days, as RootModel records them.
    readonly property int newlyInstalledRole: allAppsModel ? allAppsModel.KItemModels.KRoleNames.role("isNewlyInstalled") : -1
    readonly property KItemModels.KSortFilterProxyModel newAppsModel: KItemModels.KSortFilterProxyModel {
        sourceModel: state.allAppsModel
        filterRowCallback: (sourceRow, sourceParent) => {
            const source = state.allAppsModel;
            if (!source || state.newlyInstalledRole < 0) {
                return false;
            }
            return source.data(source.index(sourceRow, 0, sourceParent), state.newlyInstalledRole) === true;
        }
        onRowCountChanged: state.rebuildRecommended()
    }
    // Set while the new-apps filter runs again, which changes its row count.
    property bool filteringNewApps: false

    readonly property Kicker.RecentUsageModel recentDocsModel: Kicker.RecentUsageModel {
        shownItems: Kicker.RecentUsageModel.OnlyDocs
        ordering: Kicker.RecentUsageModel.Recent
        onCountChanged: state.rebuildRecommended()
    }

    // The recommended list: newly installed apps first, then recent files. Each entry is
    // { app: bool, id, display, decoration, subtitle }, where id is an app's favoriteId or a
    // file's URL. Rows move as apps and files come and go, so they're looked up when needed.
    property var recommendedItems: []

    readonly property Kicker.RunnerModel runnerModel: Kicker.RunnerModel {
        appletInterface: state.plasmoidItem
        mergeResults: true
        runners: ["krunner_services", "krunner_systemsettings", "baloosearch", "krunner_recentdocuments", "krunner_placesrunner", "krunner_appstream", "calculator", "unitconverter"]
        query: state.query
        onRequestUpdateQuery: newQuery => state.queryUpdateRequested(newQuery)
    }
    // Reading count makes this re-evaluate whenever the runners' models change, which is what
    // keeps the results up to date.
    readonly property var resultsModel: runnerModel.count ? runnerModel.modelForRow(0) : null

    readonly property Kicker.SystemModel systemModel: Kicker.SystemModel {}
    //END

    //BEGIN Pinned apps
    // A pinned ID is a bare desktop entry ID; search and recent-use models prefix "applications:".
    function normaliseId(id: string): string {
        return id.startsWith("applications:") ? id.slice("applications:".length) : id;
    }

    // Only apps can be pinned, not files, places or settings.
    function isAppId(id: string): bool {
        const bare = normaliseId(id);
        return bare.endsWith(".desktop") && !bare.includes(":") && !bare.includes("/");
    }

    function isPinned(id: string): bool {
        return state.pinnedIds.includes(normaliseId(id));
    }

    function syncFavorites() {
        state.favoritesModel.favorites = state.pinnedIds;
    }

    function storedFavorites(): var {
        return Array.from(Plasmoid.configuration.favorites ?? []).map(id => String(id));
    }

    function pin(id: string) {
        const appId = normaliseId(id);
        if (!isAppId(appId) || isPinned(appId)) {
            return;
        }
        const favorites = storedFavorites();
        favorites.push(appId);
        Plasmoid.configuration.favorites = favorites;
    }

    function unpin(id: string) {
        const appId = normaliseId(id);
        Plasmoid.configuration.favorites = storedFavorites().filter(entry => normaliseId(entry) !== appId);
    }

    function moveToFront(id: string) {
        const appId = normaliseId(id);
        const favorites = storedFavorites().filter(entry => normaliseId(entry) !== appId);
        favorites.unshift(appId);
        Plasmoid.configuration.favorites = favorites;
    }
    //END

    //BEGIN Model lookups
    function findAllAppsModel() {
        let found = null;
        for (let i = 0; i < state.rootModel.count; ++i) {
            const model = state.rootModel.modelForRow(i);
            if (model && model.description === "KICKER_ALL_MODEL") {
                found = model as Kicker.AppsModel;
                break;
            }
        }
        state.allAppsModel = found;
    }

    // The row of the app with this ID in the all-apps model, or -1.
    function allAppsRow(id: string): int {
        const model = state.allAppsModel;
        if (!model) {
            return -1;
        }
        const appId = normaliseId(id);
        const role = model.KItemModels.KRoleNames.role("favoriteId");
        for (let row = 0; row < model.count; ++row) {
            if (normaliseId(String(model.data(model.index(row, 0), role) ?? "")) === appId) {
                return row;
            }
        }
        return -1;
    }

    function allAppsData(row: int, roleName: string): var {
        const model = state.allAppsModel;
        if (!model) {
            return undefined;
        }
        return model.data(model.index(row, 0), model.KItemModels.KRoleNames.role(roleName));
    }

    function favoritesData(row: int, roleName: string): var {
        const model = state.favoritesModel;
        return model.data(model.index(row, 0), model.KItemModels.KRoleNames.role(roleName));
    }

    function recentDocsData(row: int, roleName: string): var {
        const model = state.recentDocsModel;
        return model.data(model.index(row, 0), model.KItemModels.KRoleNames.role(roleName));
    }

    // The row of the recent file with this URL, or -1.
    function recentDocsRow(url: string): int {
        const model = state.recentDocsModel;
        const role = model.KItemModels.KRoleNames.role("url");
        for (let row = 0; row < model.count; ++row) {
            if (String(model.data(model.index(row, 0), role) ?? "") === url) {
                return row;
            }
        }
        return -1;
    }

    // The row of the search result that is this match, or -1. Slower runners add and reorder
    // results while a menu is open, so a row number alone may point at another match by then.
    function resultRow(match): int {
        const model = state.resultsModel;
        if (!model) {
            return -1;
        }
        const roles = model.KItemModels.KRoleNames;
        const idRole = roles.role("favoriteId");
        const displayRole = roles.role("display");
        const urlRole = roles.role("url");
        for (let row = 0; row < model.count; ++row) {
            const index = model.index(row, 0);
            if (String(model.data(index, idRole) ?? "") === match.favoriteId
                    && String(model.data(index, displayRole) ?? "") === match.display
                    && String(model.data(index, urlRole) ?? "") === match.url) {
                return row;
            }
        }
        return -1;
    }

    function rebuildRecommended() {
        if (state.filteringNewApps) {
            return;
        }
        // An app stops counting as newly installed once it's launched, which the proxy doesn't
        // notice by itself.
        state.filteringNewApps = true;
        state.newAppsModel.invalidateFilter();
        state.filteringNewApps = false;

        const items = [];
        const newApps = state.newAppsModel;
        for (let i = 0; i < newApps.count && items.length < state.recommendedLimit; ++i) {
            const sourceRow = newApps.mapToSource(newApps.index(i, 0)).row;
            items.push({
                app: true,
                id: String(state.allAppsData(sourceRow, "favoriteId") ?? ""),
                display: String(state.allAppsData(sourceRow, "display") ?? ""),
                decoration: state.allAppsData(sourceRow, "decoration") ?? "",
                subtitle: KI18n.i18nc("@info:status An app installed in the last few days", "Recently added"),
            });
        }
        for (let row = 0; row < state.recentDocsModel.count && items.length < state.recommendedLimit; ++row) {
            items.push({
                app: false,
                id: String(state.recentDocsData(row, "url") ?? ""),
                display: String(state.recentDocsData(row, "display") ?? ""),
                decoration: state.recentDocsData(row, "decoration") ?? "",
                subtitle: String(state.recentDocsData(row, "description") ?? ""),
            });
        }
        state.recommendedItems = items;
    }
    //END

    //BEGIN Launching
    function close() {
        state.contextMenu.close();
        state.plasmoidItem.expanded = false;
    }

    function launchPinned(index: int) {
        if (state.favoritesModel.trigger(index, "", null)) {
            state.close();
        }
    }

    function launchApp(row: int) {
        if (state.allAppsModel && state.allAppsModel.trigger(row, "", null)) {
            state.close();
        }
    }

    function launchRecommended(item) {
        if (!item) {
            return;
        }
        if (item.app) {
            const row = state.allAppsRow(item.id);
            if (row >= 0) {
                state.launchApp(row);
            }
            return;
        }
        const row = state.recentDocsRow(item.id);
        if (row >= 0 && state.recentDocsModel.trigger(row, "", null)) {
            state.close();
        }
    }

    // Only Enter, or a click or Enter on a result, runs a search result; typing never does.
    function launchResult(row: int) {
        const model = state.resultsModel;
        if (model && row >= 0 && model.trigger(row, "", null)) {
            state.close();
        }
    }
    //END

    //BEGIN Context menus
    function isContextMenuKey(event: KeyEvent): bool {
        return event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier) !== 0);
    }

    // Opens the context menu for an entry of model. findRow() gives the entry's row when an
    // action runs, or -1 if it's gone. favoriteId may be empty; pinnedIndex is the tile's index
    // when the menu is for a pinned tile, otherwise -1.
    function openContextMenu(model, findRow, favoriteId: string, actionList, pinnedIndex: int, item: Item, x: real, y: real, fromKeyboard: bool) {
        const entries = [];
        const appId = isAppId(favoriteId) ? normaliseId(favoriteId) : "";
        if (appId.length > 0) {
            const pinned = isPinned(appId);
            entries.push({
                text: pinned ? KI18n.i18nc("@action:inmenu", "Unpin from Start") : KI18n.i18nc("@action:inmenu", "Pin to Start"),
                icon: pinned ? "window-unpin" : "window-pin",
                handler: () => pinned ? state.unpin(appId) : state.pin(appId),
            });
            if (pinnedIndex > 0) {
                entries.push({
                    text: KI18n.i18nc("@action:inmenu Move a pinned app to the start of the pinned apps", "Move to front"),
                    icon: "go-first",
                    handler: () => state.moveToFront(appId),
                });
            }
        }

        // The entry's own actions, without leading, doubled or trailing separators.
        const actions = [];
        for (const action of Array.from(actionList ?? [])) {
            if (action.type === "separator") {
                if (actions.length > 0 && !actions[actions.length - 1].separator) {
                    actions.push({ separator: true });
                }
            } else if (action.type === "title") {
                actions.push({ title: true, text: action.text ?? "" });
            } else {
                const actionId = action.actionId ?? "";
                const argument = action.actionArgument;
                actions.push({
                    text: action.text ?? "",
                    icon: typeof action.icon === "string" ? action.icon : "",
                    enabled: action.enabled ?? true,
                    handler: () => {
                        const row = findRow();
                        if (row >= 0 && model.trigger(row, actionId, argument)) {
                            state.close();
                        }
                    },
                });
            }
        }
        while (actions.length > 0 && actions[actions.length - 1].separator) {
            actions.pop();
        }
        if (entries.length > 0 && actions.length > 0) {
            entries.push({ separator: true });
        }
        state.contextMenu.show(entries.concat(actions), item, x, y, fromKeyboard);
    }

    function openPinnedMenu(index: int, item: Item, x: real, y: real, fromKeyboard: bool) {
        const appId = String(state.favoritesData(index, "favoriteId") ?? "");
        // The all-apps model's entry knows the applet, so its actions include adding the app to
        // the desktop or the taskbar.
        const row = state.allAppsRow(appId);
        if (row >= 0) {
            state.openContextMenu(state.allAppsModel, () => row, appId, state.allAppsData(row, "actionList"), index, item, x, y, fromKeyboard);
        } else {
            state.openContextMenu(state.favoritesModel, () => index, appId, state.favoritesData(index, "actionList"), index, item, x, y, fromKeyboard);
        }
    }

    function openAppMenu(row: int, item: Item, x: real, y: real, fromKeyboard: bool) {
        state.openContextMenu(state.allAppsModel, () => row, String(state.allAppsData(row, "favoriteId") ?? ""), state.allAppsData(row, "actionList"), -1, item, x, y, fromKeyboard);
    }

    function openRecommendedMenu(entry, item: Item, x: real, y: real, fromKeyboard: bool) {
        if (!entry) {
            return;
        }
        if (entry.app) {
            const row = state.allAppsRow(entry.id);
            if (row >= 0) {
                state.openAppMenu(row, item, x, y, fromKeyboard);
            }
            return;
        }
        const url = String(entry.id);
        const row = state.recentDocsRow(url);
        if (row >= 0) {
            state.openContextMenu(state.recentDocsModel, () => state.recentDocsRow(url), "", state.recentDocsData(row, "actionList"), -1, item, x, y, fromKeyboard);
        }
    }

    function openResultMenu(row: int, item: Item, x: real, y: real, fromKeyboard: bool) {
        const model = state.resultsModel;
        if (!model || row < 0 || row >= model.count) {
            return;
        }
        const roles = model.KItemModels.KRoleNames;
        const roleData = roleName => model.data(model.index(row, 0), roles.role(roleName));
        const match = {
            favoriteId: String(roleData("favoriteId") ?? ""),
            display: String(roleData("display") ?? ""),
            url: String(roleData("url") ?? ""),
        };
        state.openContextMenu(model, () => model === state.resultsModel ? state.resultRow(match) : -1, match.favoriteId, roleData("actionList"), -1, item, x, y, fromKeyboard);
    }
    //END

    //BEGIN Pages and focus
    function showAllApps() {
        state.showingAllApps = true;
    }

    function showHome() {
        state.showingAllApps = false;
    }

    function focusSearch() {
        state.focusRequested(MenuState.Search);
    }

    function focusPinned() {
        state.focusRequested(MenuState.Pinned);
    }

    function focusRecommended() {
        state.focusRequested(MenuState.Recommended);
    }

    function cycleFocus(forward: bool) {
        state.focusCycleRequested(forward);
    }
    //END
}
