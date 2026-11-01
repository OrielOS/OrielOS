// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.ki18n
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker
import "getstarted.js" as GetStarted

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
    // The search filter's tab: all, apps, documents, settings or folders.
    property string searchFilter: "all"
    readonly property var allRunners: ["krunner_services", "krunner_orielos_settings", "baloosearch", "krunner_recentdocuments", "krunner_placesrunner", "krunner_appstream", "calculator", "unitconverter"]
    property bool showingAllApps: false
    // Recommended's More page.
    property bool showingMore: false
    // What search shows before anything is typed: recent searches and the most used apps.
    property bool searchHome: false
    // The last searches that ran a result, newest first. Only Start writes them.
    readonly property var recentSearches: Array.from(Plasmoid.configuration.recentSearches ?? []).map(text => String(text)).filter(text => text.length > 0)
    readonly property int recentSearchLimit: 5

    readonly property int pinnedColumns: 6
    // Rows on each page of pinned apps, from the layout chosen on Settings' Start page; Recommended
    // takes the rest.
    readonly property int pinnedRows: Plasmoid.configuration.layout === "morePins" ? 3 : Plasmoid.configuration.layout === "moreRecommendations" ? 1 : 2
    readonly property int recommendedLimit: showingMore ? 30 : 6
    // What Recommended lists, set on Settings' Start page.
    readonly property bool showRecentlyAdded: Plasmoid.configuration.showRecentlyAdded ?? true
    readonly property bool showRecentFiles: Plasmoid.configuration.showRecentFiles ?? true
    // The shortcuts next to the power button, by ID, from Settings' Start page.
    // A list from the file, but whatever a script last wrote until the file is read again: a list,
    // text, or a list holding the text. Joined and split, each reads the same.
    readonly property var folders: {
        const value = Plasmoid.configuration.folders;
        return String(value ?? "").split(",").map(id => id.trim()).filter(id => id.length > 0);
    }
    onShowRecentlyAddedChanged: state.rebuildRecommended()
    onShowRecentFilesChanged: state.rebuildRecommended()

    // How All apps lists the apps: list (by letter), grid or category.
    readonly property string allAppsView: ["grid", "category"].includes(String(Plasmoid.configuration.allAppsView)) ? String(Plasmoid.configuration.allAppsView) : "list"

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

    // The apps by menu category, for All apps' Category view.
    readonly property Kicker.RootModel categoriesRootModel: Kicker.RootModel {
        appletInterface: state.plasmoidItem
        autoPopulate: false
        flat: false
        sorted: true
        showAllApps: false
        showAllAppsCategorized: true
        showTopLevelItems: false
        showRecentApps: false
        showRecentDocs: false
        showRecentFolders: false
        showPowerSession: false
        showFavoritesPlaceholder: false
        showSeparators: false

        onRefreshed: state.findCategories()
    }
    // Each category with apps: { name, icon, model }, looked up on refresh like allAppsModel.
    property var categories: []

    // The pinned apps. Plasmoid.configuration.favorites is the only record of them: the model
    // drops apps that aren't installed (yet) from its own list, so it is never written back. A
    // folder of pins takes its place in the list as "folder:<key>".
    readonly property Kicker.SimpleFavoritesModel favoritesModel: Kicker.SimpleFavoritesModel {
        onCountChanged: state.rebuildPinned()
    }
    readonly property var pinnedIds: Array.from(Plasmoid.configuration.favorites ?? []).map(id => state.normaliseId(String(id)))
    onPinnedIdsChanged: state.syncFavorites()
    // The folders of pins, by key: { name, apps }, where apps are desktop entry IDs in order.
    readonly property var pinFolders: {
        try {
            const folders = JSON.parse(String(Plasmoid.configuration.pinFolders || "{}"));
            return folders && typeof folders === "object" ? folders : {};
        } catch (error) {
            return {};
        }
    }
    onPinFoldersChanged: state.syncFavorites()
    // Every app in a folder, for looking up their names, icons and actions.
    readonly property var folderAppIds: Object.values(state.pinFolders).reduce((all, folder) => all.concat(Array.from(folder.apps ?? []).map(id => String(id))), [])
    readonly property Kicker.SimpleFavoritesModel folderAppsModel: Kicker.SimpleFavoritesModel {
        onCountChanged: state.rebuildPinned()
    }
    // What the pinned grid shows, in order: { folder: false, id, row } for an app, row being its
    // row in favoritesModel, or { folder: true, key, name, apps: [{ id, row }] } for a folder, rows
    // in folderAppsModel. Apps that aren't installed are left out, as the model leaves them out.
    property var pinnedEntries: []
    // The folder open over the pinned apps, by key, or "" when none is.
    property string openFolder: ""

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

    // The recommended list: newly installed apps first, then recent files, then the Get started
    // suggestions that aren't installed. Each entry is { app: bool, store: bool, id, display,
    // decoration, subtitle }, where id is an app's favoriteId, a file's URL or, for a suggestion,
    // its Flathub ID. Rows move as apps and files come and go, so they're looked up when needed.
    property var recommendedItems: []

    // The most used apps, for the search home.
    readonly property Kicker.RecentUsageModel topAppsModel: Kicker.RecentUsageModel {
        shownItems: Kicker.RecentUsageModel.OnlyApps
        ordering: Kicker.RecentUsageModel.Popular
    }

    readonly property Kicker.RunnerModel runnerModel: Kicker.RunnerModel {
        appletInterface: state.plasmoidItem
        mergeResults: true
        runners: {
            switch (state.searchFilter) {
            case "apps":
                return ["krunner_services", "krunner_appstream"];
            case "documents":
                return ["baloosearch", "krunner_recentdocuments"];
            case "settings":
                return ["krunner_orielos_settings"];
            case "folders":
                return ["krunner_placesrunner", "baloosearch"];
            }
            return state.allRunners;
        }
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
        const appId = normaliseId(id);
        return state.pinnedIds.includes(appId) || state.folderAppIds.includes(appId);
    }

    function syncFavorites() {
        state.favoritesModel.favorites = state.pinnedIds.filter(id => state.isAppId(id));
        // Bindings may not have been worked out yet while the configuration first loads.
        state.folderAppsModel.favorites = state.folderAppIds ?? [];
        state.rebuildPinned();
    }

    // The row of the app with this ID in a favourites model, or -1.
    function favoriteRow(model, id: string): int {
        const role = model.KItemModels.KRoleNames.role("favoriteId");
        for (let row = 0; row < model.count; ++row) {
            if (normaliseId(String(model.data(model.index(row, 0), role) ?? "")) === id) {
                return row;
            }
        }
        return -1;
    }

    function rebuildPinned() {
        const entries = [];
        for (const id of state.pinnedIds) {
            if (id.startsWith("folder:")) {
                const key = id.slice("folder:".length);
                const folder = state.pinFolders[key];
                if (!folder) {
                    continue;
                }
                const apps = Array.from(folder.apps ?? []).map(app => ({ id: String(app), row: state.favoriteRow(state.folderAppsModel, String(app)) }))
                    .filter(app => app.row >= 0);
                if (apps.length > 0) {
                    entries.push({ folder: true, key: key, name: String(folder.name ?? ""), apps: apps });
                }
                continue;
            }
            const row = state.favoriteRow(state.favoritesModel, id);
            if (row >= 0) {
                entries.push({ folder: false, id: id, row: row });
            }
        }
        state.pinnedEntries = entries;
    }

    // An entry's place in favorites: an app's ID or "folder:<key>".
    function entryKey(entry): string {
        return entry.folder ? "folder:" + entry.key : entry.id;
    }

    function writeFolders(folders) {
        Plasmoid.configuration.pinFolders = JSON.stringify(folders);
    }

    // A copy of the folders that can be changed and written back.
    function copyFolders(): var {
        return JSON.parse(JSON.stringify(state.pinFolders));
    }

    // Dropping one pinned app on another makes a folder of the two, as in Windows; dropping it on
    // a folder adds it there. Folders don't go into folders: dropping one moves it instead.
    function combinePinned(fromIndex: int, toIndex: int) {
        const from = state.pinnedEntries[fromIndex];
        const to = state.pinnedEntries[toIndex];
        if (!from || !to || fromIndex === toIndex) {
            return;
        }
        if (from.folder) {
            state.movePinned(fromIndex, toIndex);
            return;
        }
        const folders = state.copyFolders();
        let favorites = state.storedFavorites().filter(entry => normaliseId(entry) !== from.id);
        if (to.folder) {
            folders[to.key].apps = Array.from(folders[to.key].apps ?? []).concat([from.id]);
        } else {
            const key = Date.now().toString(36);
            folders[key] = { name: KI18n.i18nc("@title The name a new folder of pinned apps starts with", "Folder"), apps: [to.id, from.id] };
            favorites = favorites.map(entry => normaliseId(entry) === to.id ? "folder:" + key : entry);
        }
        state.writeFolders(folders);
        Plasmoid.configuration.favorites = favorites;
    }

    // Moves a pinned app or folder to just before the entry at beforeIndex, or to the end.
    function movePinned(fromIndex: int, beforeIndex: int) {
        const entries = state.pinnedEntries;
        if (fromIndex < 0 || fromIndex >= entries.length) {
            return;
        }
        const moving = state.entryKey(entries[fromIndex]);
        const before = beforeIndex >= 0 && beforeIndex < entries.length ? state.entryKey(entries[beforeIndex]) : "";
        const favorites = state.storedFavorites().filter(entry => normaliseId(entry) !== moving);
        const at = before.length > 0 ? favorites.findIndex(entry => normaliseId(entry) === before) : -1;
        favorites.splice(at < 0 ? favorites.length : at, 0, moving);
        Plasmoid.configuration.favorites = favorites;
    }

    function renameFolder(key: string, name: string) {
        const folders = state.copyFolders();
        if (!folders[key]) {
            return;
        }
        const trimmed = name.trim();
        folders[key].name = trimmed.length > 0 ? trimmed : KI18n.i18nc("@title The name a new folder of pinned apps starts with", "Folder");
        state.writeFolders(folders);
    }

    // Takes an app out of a folder, to just after the folder. A folder left with one app turns
    // back into that app, as in Windows.
    function moveOutOfFolder(key: string, id: string) {
        const folders = state.copyFolders();
        const folder = folders[key];
        if (!folder) {
            return;
        }
        const appId = normaliseId(id);
        folder.apps = Array.from(folder.apps ?? []).filter(app => app !== appId);
        let favorites = state.storedFavorites();
        const at = favorites.indexOf("folder:" + key);
        favorites.splice(at < 0 ? favorites.length : at + 1, 0, appId);
        favorites = state.dissolveSmallFolder(folders, key, favorites);
        state.writeFolders(folders);
        Plasmoid.configuration.favorites = favorites;
        if (!folders[key]) {
            state.openFolder = "";
        }
    }

    // A folder with one app left becomes that app, and an empty one goes. Returns favorites with
    // the folder's place changed, and removes it from folders.
    function dissolveSmallFolder(folders, key: string, favorites): var {
        const apps = Array.from(folders[key]?.apps ?? []);
        if (apps.length > 1) {
            return favorites;
        }
        delete folders[key];
        return apps.length === 1 ? favorites.map(entry => entry === "folder:" + key ? apps[0] : entry) : favorites.filter(entry => entry !== "folder:" + key);
    }

    function launchFolderApp(row: int) {
        if (state.folderAppsModel.trigger(row, "", null)) {
            state.close();
        }
    }

    function openFolderAppMenu(key: string, app, item: Item, x: real, y: real, fromKeyboard: bool) {
        const entries = [
            {
                text: KI18n.i18nc("@action:inmenu Take a pinned app out of its folder", "Move out of folder"),
                icon: "folder-open",
                handler: () => state.moveOutOfFolder(key, app.id),
            },
            { separator: true },
        ];
        const row = state.allAppsRow(app.id);
        const others = row >= 0
            ? state.contextEntries(state.allAppsModel, () => row, app.id, state.allAppsData(row, "actionList"), -1)
            : state.contextEntries(state.folderAppsModel, () => app.row, app.id, state.folderAppsModel.data(state.folderAppsModel.index(app.row, 0), state.folderAppsModel.KItemModels.KRoleNames.role("actionList")), -1);
        state.contextMenu.show(entries.concat(others), item, x, y, fromKeyboard);
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
        let favorites = storedFavorites().filter(entry => normaliseId(entry) !== appId);
        // An app in a folder leaves the folder.
        const folders = state.copyFolders();
        let changed = false;
        for (const key of Object.keys(folders)) {
            const apps = Array.from(folders[key].apps ?? []);
            if (apps.includes(appId)) {
                folders[key].apps = apps.filter(app => app !== appId);
                favorites = state.dissolveSmallFolder(folders, key, favorites);
                changed = true;
            }
        }
        if (changed) {
            state.writeFolders(folders);
            if (!folders[state.openFolder]) {
                state.openFolder = "";
            }
        }
        Plasmoid.configuration.favorites = favorites;
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

    function findCategories() {
        const found = [];
        const root = state.categoriesRootModel;
        for (let i = 0; i < root.count; ++i) {
            const model = root.modelForRow(i) as Kicker.AppsModel;
            if (!model || model.count === 0 || model.description === "KICKER_ALL_MODEL") {
                continue;
            }
            const index = root.index(i, 0);
            found.push({
                name: String(root.data(index, Qt.DisplayRole) ?? ""),
                icon: root.data(index, Qt.DecorationRole) ?? "",
                model: model,
            });
        }
        state.categories = found;
    }

    function setAllAppsView(view: string) {
        Plasmoid.configuration.allAppsView = view;
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

    function topAppsData(row: int, roleName: string): var {
        const model = state.topAppsModel;
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

    // Where Flatpak keeps the icons of Flathub's catalogue.
    readonly property string flathubIcons: "/var/lib/flatpak/appstream/flathub/x86_64/active/icons/128x128"

    // The desktop entry IDs of every installed app.
    function installedAppIds(): var {
        const ids = new Set();
        const model = state.allAppsModel;
        if (!model) {
            return ids;
        }
        const role = model.KItemModels.KRoleNames.role("favoriteId");
        for (let row = 0; row < model.count; ++row) {
            ids.add(state.normaliseId(String(model.data(model.index(row, 0), role) ?? "")));
        }
        return ids;
    }

    function hideGetStarted() {
        Plasmoid.configuration.getStartedHidden = true;
        state.rebuildRecommended();
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
        for (let i = 0; state.showRecentlyAdded && i < newApps.count && items.length < state.recommendedLimit; ++i) {
            const sourceRow = newApps.mapToSource(newApps.index(i, 0)).row;
            items.push({
                app: true,
                id: String(state.allAppsData(sourceRow, "favoriteId") ?? ""),
                display: String(state.allAppsData(sourceRow, "display") ?? ""),
                decoration: state.allAppsData(sourceRow, "decoration") ?? "",
                subtitle: KI18n.i18nc("@info:status An app installed in the last few days", "Recently added"),
            });
        }
        for (let row = 0; state.showRecentFiles && row < state.recentDocsModel.count && items.length < state.recommendedLimit; ++row) {
            items.push({
                app: false,
                id: String(state.recentDocsData(row, "url") ?? ""),
                display: String(state.recentDocsData(row, "display") ?? ""),
                decoration: state.recentDocsData(row, "decoration") ?? "",
                subtitle: String(state.recentDocsData(row, "description") ?? ""),
            });
        }
        if (!Plasmoid.configuration.getStartedHidden) {
            const installed = state.installedAppIds();
            for (const suggestion of GetStarted.apps) {
                if (items.length >= state.recommendedLimit) {
                    break;
                }
                if (installed.has(suggestion.id + ".desktop")) {
                    continue;
                }
                items.push({
                    app: false,
                    store: true,
                    id: suggestion.id,
                    display: suggestion.name,
                    // Flathub's own icon, once the Store has fetched Flathub's catalogue.
                    decoration: "file://" + state.flathubIcons + "/" + suggestion.id + ".png",
                    subtitle: KI18n.i18nc("@info An app the user can get from the Store", "Get it from the Store"),
                });
            }
        }
        state.recommendedItems = items;
    }
    //END

    //BEGIN Launching
    function close() {
        state.contextMenu.close();
        state.plasmoidItem.expanded = false;
        state.searchFilter = "all";
        state.openFolder = "";
    }

    // Opens a pinned app, or opens a folder in place over the pinned apps.
    function launchPinned(index: int) {
        const entry = state.pinnedEntries[index];
        if (!entry) {
            return;
        }
        if (entry.folder) {
            state.openFolder = entry.key;
            return;
        }
        if (state.favoritesModel.trigger(entry.row, "", null)) {
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
        // A suggestion opens its page in the Store, which installs nothing until asked to.
        if (item.store) {
            Qt.openUrlExternally("appstream://" + item.id);
            state.close();
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
        const query = state.query.trim();
        if (model && row >= 0 && model.trigger(row, "", null)) {
            state.rememberSearch(query);
            state.close();
        }
    }

    function launchTopApp(row: int) {
        if (row >= 0 && state.topAppsModel.trigger(row, "", null)) {
            state.close();
        }
    }
    //END

    //BEGIN Recent searches
    // A search that ran a result goes first; the same words in other letter cases only once.
    function rememberSearch(text: string) {
        if (text.length === 0) {
            return;
        }
        const others = state.recentSearches.filter(entry => entry.toLowerCase() !== text.toLowerCase());
        Plasmoid.configuration.recentSearches = [text].concat(others).slice(0, state.recentSearchLimit);
    }

    function forgetSearch(text: string) {
        Plasmoid.configuration.recentSearches = state.recentSearches.filter(entry => entry !== text);
    }

    function clearSearches() {
        Plasmoid.configuration.recentSearches = [];
    }

    // Puts a recent search back in the search field, which shows its results.
    function searchAgain(text: string) {
        state.queryUpdateRequested(text);
    }
    //END

    //BEGIN Context menus
    function isContextMenuKey(event: KeyEvent): bool {
        return event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier) !== 0);
    }

    // Plasma names its pinning actions after its own widgets: the taskbar's app list is the "Task
    // Manager" there, which OrielOS users know as the process tool. Start names the three places an
    // app can be pinned instead: Start, the taskbar and the desktop.
    function actionLabel(actionId: string, plasmaText: string): string {
        switch (actionId) {
        case "addToTaskManager":
        case "addToPanel":
            return KI18n.i18nc("@action:inmenu Pin an app to the taskbar", "Pin to taskbar");
        case "addToDesktop":
            return KI18n.i18nc("@action:inmenu Put an app's icon on the desktop", "Pin to desktop");
        default:
            return plasmaText;
        }
    }

    // Opens the context menu for an entry of model. findRow() gives the entry's row when an
    // action runs, or -1 if it's gone. favoriteId may be empty; pinnedIndex is the tile's index
    // when the menu is for a pinned tile, otherwise -1.
    function openContextMenu(model, findRow, favoriteId: string, actionList, pinnedIndex: int, item: Item, x: real, y: real, fromKeyboard: bool) {
        state.contextMenu.show(state.contextEntries(model, findRow, favoriteId, actionList, pinnedIndex), item, x, y, fromKeyboard);
    }

    // The entries of an entry's context menu, as openContextMenu shows them and the search's
    // actions pane lists them: { text, icon, handler }, or { separator } or { title, text }.
    // Files pinned to an app's jump list, newest first. Plasmoid.configuration.pinnedFiles keeps them
    // as the app's ID, a tab and the file's URL.
    function pinnedFilesOf(appId: string): var {
        const prefix = appId + "\t";
        return Array.from(Plasmoid.configuration.pinnedFiles ?? []).map(entry => String(entry))
            .filter(entry => entry.startsWith(prefix)).map(entry => entry.slice(prefix.length));
    }
    function setFilePinned(appId: string, url: string, pinned: bool) {
        const key = appId + "\t" + url;
        const files = Array.from(Plasmoid.configuration.pinnedFiles ?? []).map(entry => String(entry)).filter(entry => entry !== key);
        if (pinned) {
            files.unshift(key);
        }
        Plasmoid.configuration.pinnedFiles = files;
    }
    function fileNameOf(url: string): string {
        return decodeURIComponent(url.split("/").pop() || url);
    }

    function contextEntries(model, findRow, favoriteId: string, actionList, pinnedIndex: int): var {
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

        // The entry's own actions, without leading, doubled or trailing separators. Its recent files
        // can be pinned to the list, and pinned ones show under their own heading above them.
        const pinnedFiles = appId.length > 0 ? state.pinnedFilesOf(appId) : [];
        const fileIcons = {};
        let recentAt = -1;
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
                if (actionId === "_kicker_recentDocument" && appId.length > 0) {
                    const url = String(Array.from(argument ?? [])[0] ?? "");
                    fileIcons[url] = typeof action.icon === "string" ? action.icon : "";
                    if (recentAt < 0) {
                        // Before the Recent Files heading.
                        recentAt = actions.length > 0 && actions[actions.length - 1].title ? actions.length - 1 : actions.length;
                    }
                    if (pinnedFiles.includes(url)) {
                        continue;
                    }
                    actions.push({
                        text: String(action.text ?? ""),
                        icon: fileIcons[url],
                        pin: { pinned: false, handler: () => state.setFilePinned(appId, url, true) },
                        handler: () => {
                            const row = findRow();
                            if (row >= 0 && model.trigger(row, actionId, argument)) {
                                state.close();
                            }
                        },
                    });
                    continue;
                }
                actions.push({
                    text: state.actionLabel(actionId, String(action.text ?? "")),
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
        if (pinnedFiles.length > 0) {
            const pinned = [{ title: true, text: KI18n.i18nc("@title Files pinned to an app's jump list", "Pinned") }];
            for (const url of pinnedFiles) {
                pinned.push({
                    text: state.fileNameOf(url),
                    icon: fileIcons[url] || "text-x-generic",
                    pin: { pinned: true, handler: () => state.setFilePinned(appId, url, false) },
                    handler: () => {
                        Plasmoid.openFileWith(appId, url); // qmllint disable missing-property
                        state.close();
                    },
                });
            }
            if (recentAt < 0) {
                if (actions.length > 0 && !actions[actions.length - 1].separator) {
                    actions.push({ separator: true });
                }
                recentAt = actions.length;
            }
            actions.splice(recentAt, 0, ...pinned);
        }
        // A Recent Files heading with every file pinned has nothing under it.
        for (let i = actions.length - 1; i >= 0; --i) {
            if (actions[i].title && (i + 1 >= actions.length || actions[i + 1].title || actions[i + 1].separator)) {
                actions.splice(i, 1);
            }
        }
        while (actions.length > 0 && actions[actions.length - 1].separator) {
            actions.pop();
        }
        if (entries.length > 0 && actions.length > 0) {
            entries.push({ separator: true });
        }
        return entries.concat(actions);
    }

    function openPinnedMenu(index: int, item: Item, x: real, y: real, fromKeyboard: bool) {
        const entry = state.pinnedEntries[index];
        if (!entry || entry.folder) {
            return;
        }
        const appId = entry.id;
        const favoriteRow = entry.row;
        // The all-apps model's entry knows the applet, so its actions include adding the app to
        // the desktop or the taskbar.
        const row = state.allAppsRow(appId);
        if (row >= 0) {
            state.openContextMenu(state.allAppsModel, () => row, appId, state.allAppsData(row, "actionList"), index, item, x, y, fromKeyboard);
        } else {
            state.openContextMenu(state.favoritesModel, () => favoriteRow, appId, state.favoritesData(favoriteRow, "actionList"), index, item, x, y, fromKeyboard);
        }
    }

    // The menu of an app listed by another model. The all-apps model's entry knows the applet, so
    // its actions include pinning to the taskbar.
    function openOtherAppMenu(model, row: int, item: Item, x: real, y: real, fromKeyboard: bool) {
        const roles = model.KItemModels.KRoleNames;
        const appId = String(model.data(model.index(row, 0), roles.role("favoriteId")) ?? "");
        const appsRow = state.allAppsRow(appId);
        if (appsRow >= 0) {
            state.openAppMenu(appsRow, item, x, y, fromKeyboard);
        } else {
            state.openContextMenu(model, () => row, appId, model.data(model.index(row, 0), roles.role("actionList")), -1, item, x, y, fromKeyboard);
        }
    }

    function openTopAppMenu(row: int, item: Item, x: real, y: real, fromKeyboard: bool) {
        state.openOtherAppMenu(state.topAppsModel, row, item, x, y, fromKeyboard);
    }

    function launchFrom(model, row: int) {
        if (model && row >= 0 && model.trigger(row, "", null)) {
            state.close();
        }
    }

    function openAppMenu(row: int, item: Item, x: real, y: real, fromKeyboard: bool) {
        state.openContextMenu(state.allAppsModel, () => row, String(state.allAppsData(row, "favoriteId") ?? ""), state.allAppsData(row, "actionList"), -1, item, x, y, fromKeyboard);
    }

    function openRecommendedMenu(entry, item: Item, x: real, y: real, fromKeyboard: bool) {
        if (!entry) {
            return;
        }
        if (entry.store) {
            state.contextMenu.show([
                {
                    text: KI18n.i18nc("@action:inmenu", "Open in the Store"),
                    icon: "plasmadiscover",
                    handler: () => state.launchRecommended(entry),
                },
                { separator: true },
                {
                    text: KI18n.i18nc("@action:inmenu Hide the list of suggested apps", "Hide these suggestions"),
                    icon: "view-hidden",
                    handler: () => state.hideGetStarted(),
                },
            ], item, x, y, fromKeyboard);
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
        const entries = state.resultEntries(row);
        if (entries.length > 0) {
            state.contextMenu.show(entries, item, x, y, fromKeyboard);
        }
    }

    // The heading for a kind of search result: Discover's results are the Store's.
    readonly property string storeSearchName: String(Plasmoid.storeSearchName ?? "") // qmllint disable missing-property
    function groupTitle(group: string): string {
        return group.length > 0 && group === state.storeSearchName ? KI18n.i18nc("@title Search results from the Store", "Store") : group;
    }

    // A search result's kind, such as Applications or Settings.
    function resultGroup(row: int): string {
        const model = state.resultsModel;
        if (!model || row < 0 || row >= model.count) {
            return "";
        }
        const roles = model.KItemModels.KRoleNames;
        return state.groupTitle(String(model.data(model.index(row, 0), roles.role("group")) ?? ""));
    }

    // A search result's actions, for its context menu and the actions pane.
    function resultEntries(row: int): var {
        const model = state.resultsModel;
        if (!model || row < 0 || row >= model.count) {
            return [];
        }
        const roles = model.KItemModels.KRoleNames;
        const roleData = roleName => model.data(model.index(row, 0), roles.role(roleName));
        const match = {
            favoriteId: String(roleData("favoriteId") ?? ""),
            display: String(roleData("display") ?? ""),
            url: String(roleData("url") ?? ""),
        };
        return state.contextEntries(model, () => model === state.resultsModel ? state.resultRow(match) : -1, match.favoriteId, roleData("actionList"), -1);
    }
    //END

    //BEGIN Pages and focus
    function showAllApps() {
        state.showingMore = false;
        state.searchHome = false;
        state.showingAllApps = true;
    }

    function showMore() {
        state.showingAllApps = false;
        state.searchHome = false;
        state.showingMore = true;
        state.rebuildRecommended();
    }

    function showSearchHome() {
        state.showingAllApps = false;
        state.showingMore = false;
        state.searchHome = true;
    }

    function showHome() {
        const wasMore = state.showingMore;
        state.showingAllApps = false;
        state.showingMore = false;
        state.searchHome = false;
        state.openFolder = "";
        if (wasMore) {
            state.rebuildRecommended();
        }
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
