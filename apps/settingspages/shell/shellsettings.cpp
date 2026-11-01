// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "shellsettings.h"

#include <KLocalizedString>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace OrielOSSettingsPages {

namespace {

// Finds OrielOS's Start menu, the panel it's on and the panel spacer just before it, makes the
// change (in place of the CHANGE comment), and prints the settings as JSON. Plasma's desktop
// scripting writes a widget's setting through its configuration, so the widget follows at once.
const char *const scriptTemplate = R"JS(
function flag(value) {
    return value !== false && String(value) !== "false";
}

// The panel's widget ids in the order shown: the saved order first, then any others.
function order(panel) {
    var ids = panel.widgetIds;
    panel.currentConfigGroup = ["General"];
    var saved = String(panel.readConfig("AppletOrder", "")).split(";")
        .map(function (id) { return Number(id); })
        .filter(function (id) { return ids.indexOf(id) >= 0; });
    ids.forEach(function (id) {
        if (saved.indexOf(id) < 0) {
            saved.push(id);
        }
    });
    return saved;
}

var state = { hasStart: false };
var panel = null;
// The first widget of a type on the taskbar, with its General settings at hand, or null.
function first(type) {
    var found = panel.widgets(type);
    if (found.length === 0) {
        return null;
    }
    found[0].currentConfigGroup = ["General"];
    return found[0];
}

// Start's folders next to the power button, in Windows' order.
var folderOrder = ["settings", "files", "documents", "downloads", "music", "pictures", "videos", "network", "personal"];
function startFolders() {
    return String(start.readConfig("folders", "files,downloads,settings")).split(",").filter(function (id) {
        return folderOrder.indexOf(id) >= 0;
    });
}
function setStartFolder(id, shown) {
    var folders = startFolders().filter(function (other) { return other !== id; });
    if (shown) {
        folders.push(id);
    }
    folders.sort(function (a, b) { return folderOrder.indexOf(a) - folderOrder.indexOf(b); });
    // A list, as Start reads it; text would reach Start as one string until the file is read again.
    start.writeConfig("folders", folders);
    start.reloadConfig();
}

// The apps whose icons the tray shows on the taskbar, by id, in their order there.
function trayShown() {
    var shown = tray.readConfig("shownItems", []);
    // Read back from the file before the widget has it, the list is text.
    if (typeof shown === "string") {
        shown = shown.split(",");
    }
    return Array.prototype.slice.call(shown).map(String).filter(function (id) { return id !== ""; });
}
// A newly shown icon goes at the end, beside the clock.
function setTrayShown(id, shown) {
    var ids = trayShown().filter(function (other) { return other !== id; });
    if (shown) {
        ids.push(id);
    }
    tray.writeConfig("shownItems", ids);
    tray.reloadConfig();
}

// Whether a panel is one of the taskbars added for the other displays.
function isExtraTaskbar(other) {
    other.currentConfigGroup = ["General"];
    return flag(other.readConfig("orielosExtraTaskbar", false));
}

// Adds a taskbar to every display that has none, laid out as the main one with Start, Search, Task
// View, the display's own windows, the clock and the show desktop strip (the system tray stays on
// the main display, as in Windows); with show false, takes them away again.
function taskbarsEverywhere(show) {
    all.filter(isExtraTaskbar).forEach(function (other) {
        if (!show) {
            other.remove();
        }
    });
    if (show) {
        for (var screen = 0; screen < screenCount; ++screen) {
            var covered = panels().some(function (other) {
                return other.screen === screen && other.widgets("org.orielos.startmenu").length > 0;
            });
            if (covered) {
                continue;
            }
            var extra = new Panel;
            extra.screen = screen;
            extra.location = "bottom";
            extra.height = panel.height;
            extra.lengthMode = "fill";
            extra.floating = false;
            extra.hiding = panel.hiding;
            extra.currentConfigGroup = ["General"];
            extra.writeConfig("orielosExtraTaskbar", true);
            extra.addWidget("org.kde.plasma.panelspacer");
            var extraStart = extra.addWidget("org.orielos.startmenu");
            extraStart.currentConfigGroup = ["General"];
            extraStart.writeConfig("icon", "orielos-start");
            extraStart.writeConfig("favorites", start.readConfig("favorites", ""));
            extra.addWidget("org.orielos.search");
            extra.addWidget("org.orielos.taskview");
            var extraTasks = extra.addWidget(tasks ? tasks.type : "org.kde.plasma.icontasks");
            extraTasks.currentConfigGroup = ["General"];
            if (tasks) {
                extraTasks.writeConfig("launchers", tasks.readConfig("launchers", ""));
                extraTasks.writeConfig("groupingStrategy", tasks.readConfig("groupingStrategy", 1));
            }
            extraTasks.writeConfig("fill", false);
            extraTasks.writeConfig("showOnlyCurrentScreen", true);
            extra.addWidget("org.kde.plasma.panelspacer");
            extra.addWidget("org.orielos.clock");
            extra.addWidget("org.orielos.showdesktop");
        }
    }
    // With a taskbar on every display, each lists that display's windows.
    if (tasks) {
        tasks.writeConfig("showOnlyCurrentScreen", show);
        tasks.reloadConfig();
    }
}

// Puts a task manager of another kind in the old one's place, with all its settings (pinned apps
// among them). Plasma's icon-only task manager and its labelled one are the same code under two
// names, and which name a widget has decides whether its buttons show the windows' titles.
function replaceTasks(old, type, inPanel) {
    var keys = old.configKeys;
    var values = {};
    keys.forEach(function (key) { values[key] = old.readConfig(key); });
    var place = old.geometry;
    // Added at the old one's coordinates, the panel puts it in the old one's place.
    var replacement = (inPanel || panel).addWidget(type, place.x + 2, place.y + 2, place.width, place.height);
    replacement.currentConfigGroup = ["General"];
    keys.forEach(function (key) { replacement.writeConfig(key, values[key]); });
    old.remove();
    return replacement;
}

// Combined, each app's windows share one icon (grouping 1); never combined, each window gets its
// own button with its title, as Windows shows them. On every taskbar, the other displays' too.
function combineEverywhere(combine) {
    var wanted = combine ? "org.kde.plasma.icontasks" : "org.kde.plasma.taskmanager";
    var change = function (old, inPanel) {
        old.currentConfigGroup = ["General"];
        var changed = old.type === wanted ? old : replaceTasks(old, wanted, inPanel);
        changed.writeConfig("groupingStrategy", combine ? 1 : 0);
        changed.reloadConfig();
        return changed;
    };
    if (tasks) {
        tasks = change(tasks, panel);
    }
    panels().filter(isExtraTaskbar).forEach(function (extra) {
        extra.widgets("org.kde.plasma.icontasks").concat(extra.widgets("org.kde.plasma.taskmanager")).forEach(function (old) {
            change(old, extra);
        });
    });
}
var start = null;
var all = panels();
for (var i = 0; i < all.length && !start; ++i) {
    var found = all[i].widgets("org.orielos.startmenu");
    if (found.length > 0) {
        panel = all[i];
        start = found[0];
    }
}
if (start) {
    var ids = order(panel);
    var at = ids.indexOf(start.id);
    var before = at > 0 ? panel.widgetById(ids[at - 1]) : null;
    var spacer = before && before.type === "org.kde.plasma.panelspacer" ? before : null;
    start.currentConfigGroup = ["General"];
    if (spacer) {
        spacer.currentConfigGroup = ["General"];
    }
    var search = first("org.orielos.search");
    var taskView = first("org.orielos.taskview");
    var tasks = first("org.kde.plasma.icontasks") || first("org.kde.plasma.taskmanager");
    var clock = first("org.orielos.clock");
    var sliver = first("org.orielos.showdesktop");
    var tray = first("org.orielos.tray");
    /*CHANGE*/
    state.hasStart = true;
    state.showRecentlyAdded = flag(start.readConfig("showRecentlyAdded", true));
    state.showRecentFiles = flag(start.readConfig("showRecentFiles", true));
    state.canAlign = spacer !== null;
    state.centred = spacer === null || flag(spacer.readConfig("expanding", true));
    state.autoHide = panel.hiding === "autohide";
    state.hasSearch = search !== null;
    state.showSearch = search === null || flag(search.readConfig("shown", true));
    state.hasTaskView = taskView !== null;
    state.showTaskView = taskView === null || flag(taskView.readConfig("shown", true));
    state.hasTasks = tasks !== null;
    // Combined: the icon-only task manager, grouping by app (1, Plasma's default); never combined:
    // the labelled one, not grouping (0).
    state.combineButtons = tasks === null
        || (tasks.type === "org.kde.plasma.icontasks" && String(tasks.readConfig("groupingStrategy", 1)) !== "0");
    state.hasClock = clock !== null;
    state.showSeconds = clock !== null && flag(clock.readConfig("showSeconds", false));
    state.hasSliver = sliver !== null;
    state.peek = sliver !== null && flag(sliver.readConfig("peek", false));
    state.allDisplays = panels().some(isExtraTaskbar);
    state.smallButtons = panel.height < 48;
    state.startFolders = startFolders();
    state.startLayout = String(start.readConfig("layout", "default"));
    state.hasTray = tray !== null;
    state.trayShown = tray ? trayShown() : [];
}
print(JSON.stringify(state));
)JS";

QString changeScript(const ShellSettings::Change &change)
{
    const QString value = change.value ? QStringLiteral("true") : QStringLiteral("false");
    switch (change.setting) {
    case ShellSettings::Setting::ShowRecentlyAdded:
        return QStringLiteral("start.writeConfig(\"showRecentlyAdded\", %1);\n    start.reloadConfig();").arg(value);
    case ShellSettings::Setting::ShowRecentFiles:
        return QStringLiteral("start.writeConfig(\"showRecentFiles\", %1);\n    start.reloadConfig();").arg(value);
    case ShellSettings::Setting::Centred:
        // Left-aligned, the spacer shrinks to nothing and the one after Start fills the panel.
        return QStringLiteral("if (spacer) {\n        spacer.writeConfig(\"expanding\", %1);\n        spacer.reloadConfig();\n    }").arg(value);
    case ShellSettings::Setting::AutoHide:
        return QStringLiteral("panel.hiding = %1 ? \"autohide\" : \"none\";").arg(value);
    case ShellSettings::Setting::ShowSearch:
        return QStringLiteral("if (search) {\n        search.writeConfig(\"shown\", %1);\n        search.reloadConfig();\n    }").arg(value);
    case ShellSettings::Setting::ShowTaskView:
        return QStringLiteral("if (taskView) {\n        taskView.writeConfig(\"shown\", %1);\n        taskView.reloadConfig();\n    }").arg(value);
    case ShellSettings::Setting::CombineButtons:
        return QStringLiteral("combineEverywhere(%1);").arg(value);
    case ShellSettings::Setting::ShowSeconds:
        return QStringLiteral("if (clock) {\n        clock.writeConfig(\"showSeconds\", %1);\n        clock.reloadConfig();\n    }").arg(value);
    case ShellSettings::Setting::Peek:
        return QStringLiteral("if (sliver) {\n        sliver.writeConfig(\"peek\", %1);\n        sliver.reloadConfig();\n    }").arg(value);
    case ShellSettings::Setting::AllDisplays:
        return QStringLiteral("taskbarsEverywhere(%1);").arg(value);
    case ShellSettings::Setting::SmallButtons:
        // Every taskbar, the other displays' too: 40 px high with smaller buttons, or the usual 48.
        return QStringLiteral("[panel].concat(panels().filter(isExtraTaskbar)).forEach(function (bar) {\n        bar.height = %1 ? 40 : 48;\n    });")
            .arg(value);
    case ShellSettings::Setting::FolderSettings:
    case ShellSettings::Setting::FolderFiles:
    case ShellSettings::Setting::FolderDocuments:
    case ShellSettings::Setting::FolderDownloads:
    case ShellSettings::Setting::FolderMusic:
    case ShellSettings::Setting::FolderPictures:
    case ShellSettings::Setting::FolderVideos:
    case ShellSettings::Setting::FolderNetwork:
    case ShellSettings::Setting::FolderPersonal:
        return QStringLiteral("setStartFolder(\"%1\", %2);").arg(ShellSettings::folderId(change.setting), value);
    case ShellSettings::Setting::LayoutMorePins:
    case ShellSettings::Setting::LayoutDefault:
    case ShellSettings::Setting::LayoutMoreRecommendations:
        if (!change.value) {
            return { };
        }
        return QStringLiteral("start.writeConfig(\"layout\", \"%1\");\n    start.reloadConfig();").arg(ShellSettings::layoutId(change.setting));
    case ShellSettings::Setting::TrayIcon: {
        // The id goes in as JSON, so no app's id can break out of its string.
        const QString id = QString::fromUtf8(QJsonDocument(QJsonArray { change.item }).toJson(QJsonDocument::Compact));
        return QStringLiteral("if (tray) {\n        setTrayShown(%1[0], %2);\n    }").arg(id, value);
    }
    }
    return { };
}

} // namespace

std::optional<ShellState> ShellState::fromJson(const QString &json)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(json.trimmed().toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject() || !document.object().value(QStringLiteral("hasStart")).isBool()) {
        return std::nullopt;
    }
    const QJsonObject object = document.object();
    ShellState state;
    state.hasStart = object.value(QStringLiteral("hasStart")).toBool();
    state.showRecentlyAdded = object.value(QStringLiteral("showRecentlyAdded")).toBool(true);
    state.showRecentFiles = object.value(QStringLiteral("showRecentFiles")).toBool(true);
    state.canAlign = object.value(QStringLiteral("canAlign")).toBool(false);
    state.centred = object.value(QStringLiteral("centred")).toBool(true);
    state.autoHide = object.value(QStringLiteral("autoHide")).toBool(false);
    state.hasSearch = object.value(QStringLiteral("hasSearch")).toBool(false);
    state.showSearch = object.value(QStringLiteral("showSearch")).toBool(true);
    state.hasTaskView = object.value(QStringLiteral("hasTaskView")).toBool(false);
    state.showTaskView = object.value(QStringLiteral("showTaskView")).toBool(true);
    state.hasTasks = object.value(QStringLiteral("hasTasks")).toBool(false);
    state.combineButtons = object.value(QStringLiteral("combineButtons")).toBool(true);
    state.hasClock = object.value(QStringLiteral("hasClock")).toBool(false);
    state.showSeconds = object.value(QStringLiteral("showSeconds")).toBool(false);
    state.allDisplays = object.value(QStringLiteral("allDisplays")).toBool(false);
    state.hasSliver = object.value(QStringLiteral("hasSliver")).toBool(false);
    state.peek = object.value(QStringLiteral("peek")).toBool(false);
    state.smallButtons = object.value(QStringLiteral("smallButtons")).toBool(false);
    if (object.value(QStringLiteral("startLayout")).isString()) {
        state.startLayout = object.value(QStringLiteral("startLayout")).toString();
    }
    state.hasTray = object.value(QStringLiteral("hasTray")).toBool(false);
    for (const QJsonValue &id : object.value(QStringLiteral("trayShown")).toArray()) {
        state.trayShown.append(id.toString());
    }
    if (object.value(QStringLiteral("startFolders")).isArray()) {
        state.startFolders.clear();
        for (const QJsonValue &id : object.value(QStringLiteral("startFolders")).toArray()) {
            state.startFolders.append(id.toString());
        }
    }
    return state;
}

ShellSettings::ShellSettings(QObject *parent)
    : QObject(parent)
{
    m_runner = [this](const QString &script, std::function<void(bool, const QString &)> done) {
        QDBusMessage message = QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"), QStringLiteral("org.kde.PlasmaShell"), QStringLiteral("evaluateScript"));
        message << script;
        // Parented to this, so no answer arrives after the settings are gone.
        auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [watcher, done = std::move(done)]() {
            watcher->deleteLater();
            const QDBusPendingReply<QString> reply = *watcher;
            if (reply.isError()) {
                done(false, reply.error().message());
            } else {
                done(true, reply.value());
            }
        });
    };
    reload();
}

ShellSettings::ShellSettings(Runner runner, QObject *parent)
    : QObject(parent)
    , m_runner(std::move(runner))
{
    reload();
}

ShellState ShellSettings::state() const
{
    ShellState shown = m_confirmed;
    for (const std::optional<Change> &change : m_queue) {
        if (change) {
            apply(shown, *change);
        }
    }
    return shown;
}

void ShellSettings::reload()
{
    m_queue.append(std::nullopt);
    runNext();
}

void ShellSettings::change(Setting setting, bool value)
{
    if (setting == Setting::TrayIcon) {
        return;
    }
    m_queue.append(Change { setting, value });
    // The script starts first, so anything that reacts to changed() by changing more only queues.
    runNext();
    Q_EMIT changed();
}

void ShellSettings::changeTrayIcon(const QString &item, bool shown)
{
    m_queue.append(Change { Setting::TrayIcon, shown, item });
    runNext();
    Q_EMIT changed();
}

QString ShellSettings::script(std::optional<Change> change)
{
    return QString::fromUtf8(scriptTemplate).replace(QStringLiteral("/*CHANGE*/"), change ? changeScript(*change) : QString());
}

void ShellSettings::runNext()
{
    if (m_running || m_queue.isEmpty()) {
        return;
    }
    m_running = true;
    m_runner(script(m_queue.first()), [this](bool ok, const QString &output) { finish(ok, output); });
}

void ShellSettings::finish(bool ok, const QString &output)
{
    m_running = false;
    const std::optional<Change> job = m_queue.takeFirst();
    std::optional<ShellState> read = ok ? ShellState::fromJson(output) : std::nullopt;
    if (read) {
        m_confirmed = *read;
        m_error.clear();
    } else {
        m_error = job ? i18nc("@info", "The change couldn't be made.") : i18nc("@info", "The taskbar's settings couldn't be read.");
    }
    m_ready = true;
    runNext();
    Q_EMIT changed();
}

void ShellSettings::apply(ShellState &state, const Change &change)
{
    switch (change.setting) {
    case Setting::ShowRecentlyAdded:
        state.showRecentlyAdded = change.value;
        break;
    case Setting::ShowRecentFiles:
        state.showRecentFiles = change.value;
        break;
    case Setting::Centred:
        state.centred = change.value;
        break;
    case Setting::AutoHide:
        state.autoHide = change.value;
        break;
    case Setting::ShowSearch:
        state.showSearch = change.value;
        break;
    case Setting::ShowTaskView:
        state.showTaskView = change.value;
        break;
    case Setting::CombineButtons:
        state.combineButtons = change.value;
        break;
    case Setting::ShowSeconds:
        state.showSeconds = change.value;
        break;
    case Setting::Peek:
        state.peek = change.value;
        break;
    case Setting::AllDisplays:
        state.allDisplays = change.value;
        break;
    case Setting::SmallButtons:
        state.smallButtons = change.value;
        break;
    case Setting::LayoutMorePins:
    case Setting::LayoutDefault:
    case Setting::LayoutMoreRecommendations:
        if (change.value) {
            state.startLayout = layoutId(change.setting);
        }
        break;
    case Setting::TrayIcon:
        state.trayShown.removeAll(change.item);
        if (change.value) {
            state.trayShown.append(change.item);
        }
        break;
    default: {
        const QString id = folderId(change.setting);
        if (!id.isEmpty()) {
            state.startFolders.removeAll(id);
            if (change.value) {
                state.startFolders.append(id);
            }
        }
        break;
    }
    }
}

namespace {
const QStringList folderIds = { QStringLiteral("settings"), QStringLiteral("files"), QStringLiteral("documents"), QStringLiteral("downloads"),
    QStringLiteral("music"), QStringLiteral("pictures"), QStringLiteral("videos"), QStringLiteral("network"), QStringLiteral("personal") };
} // namespace

QString ShellSettings::layoutId(Setting setting)
{
    switch (setting) {
    case Setting::LayoutMorePins:
        return QStringLiteral("morePins");
    case Setting::LayoutDefault:
        return QStringLiteral("default");
    case Setting::LayoutMoreRecommendations:
        return QStringLiteral("moreRecommendations");
    default:
        return { };
    }
}

QString ShellSettings::folderId(Setting setting)
{
    const int index = int(setting) - int(Setting::FolderSettings);
    return index >= 0 && index < folderIds.size() ? folderIds.at(index) : QString();
}

std::optional<ShellSettings::Setting> ShellSettings::folderSetting(const QString &id)
{
    const qsizetype index = folderIds.indexOf(id);
    if (index < 0) {
        return std::nullopt;
    }
    return Setting(int(Setting::FolderSettings) + int(index));
}

} // namespace OrielOSSettingsPages
