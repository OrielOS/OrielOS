// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "shellsettings.h"

#include <KLocalizedString>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
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
    var tasks = first("org.kde.plasma.icontasks");
    var clock = first("org.orielos.clock");
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
    // 1 groups by app, Plasma's default; 0 doesn't group.
    state.combineButtons = tasks === null || String(tasks.readConfig("groupingStrategy", 1)) !== "0";
    state.hasClock = clock !== null;
    state.showSeconds = clock !== null && flag(clock.readConfig("showSeconds", false));
}
print(JSON.stringify(state));
)JS";

QString changeScript(const ShellSettings::Change &change)
{
    const QString value = change.second ? QStringLiteral("true") : QStringLiteral("false");
    switch (change.first) {
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
        // 1 groups each app's windows on one button, Plasma's default; 0 gives each its own.
        return QStringLiteral("if (tasks) {\n        tasks.writeConfig(\"groupingStrategy\", %1 ? 1 : 0);\n        tasks.reloadConfig();\n    }").arg(value);
    case ShellSettings::Setting::ShowSeconds:
        return QStringLiteral("if (clock) {\n        clock.writeConfig(\"showSeconds\", %1);\n        clock.reloadConfig();\n    }").arg(value);
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
    m_queue.append(Change { setting, value });
    // The script starts first, so anything that reacts to changed() by changing more only queues.
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
    switch (change.first) {
    case Setting::ShowRecentlyAdded:
        state.showRecentlyAdded = change.second;
        break;
    case Setting::ShowRecentFiles:
        state.showRecentFiles = change.second;
        break;
    case Setting::Centred:
        state.centred = change.second;
        break;
    case Setting::AutoHide:
        state.autoHide = change.second;
        break;
    case Setting::ShowSearch:
        state.showSearch = change.second;
        break;
    case Setting::ShowTaskView:
        state.showTaskView = change.second;
        break;
    case Setting::CombineButtons:
        state.combineButtons = change.second;
        break;
    case Setting::ShowSeconds:
        state.showSeconds = change.second;
        break;
    }
}

} // namespace OrielOSSettingsPages
