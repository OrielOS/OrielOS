// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "steamlibrary.h"

#include "vdf.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>

#include <algorithm>
#include <optional>
#include <utility>

namespace OrielOSGames {

namespace {

const QStringList compatPath = { QStringLiteral("InstallConfigStore"), QStringLiteral("Software"), QStringLiteral("Valve"), QStringLiteral("Steam"),
    QStringLiteral("CompatToolMapping") };

std::optional<VdfNode> readVdf(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return std::nullopt;
    }
    return parseVdf(QString::fromUtf8(file.readAll()));
}

// Steam's own tools, which it lists among the apps it installed.
bool isTool(const QString &name)
{
    static const QRegularExpression tools(QStringLiteral("^(Proton|Steam Linux Runtime|Steamworks Common Redistributables|SteamVR)"));
    return tools.match(name).hasMatch();
}

QString artFor(const QString &root, const QString &appId)
{
    const QString cache = root + QStringLiteral("/appcache/librarycache/");
    // Newer Steam keeps each game's art in a folder of its own; older Steam named files by app.
    for (const QString &candidate : { cache + appId + QStringLiteral("/library_600x900.jpg"), cache + appId + QStringLiteral("_library_600x900.jpg"),
             cache + appId + QStringLiteral("/header.jpg"), cache + appId + QStringLiteral("_header.jpg") }) {
        if (QFileInfo::exists(candidate)) {
            return candidate;
        }
    }
    return { };
}

// Every app Steam installed in the libraries, from their manifests: app ID and name.
QList<SteamGame> manifests(const QStringList &libraries)
{
    QList<SteamGame> out;
    for (const QString &library : libraries) {
        const QDir apps(library + QStringLiteral("/steamapps"));
        for (const QString &file : apps.entryList({ QStringLiteral("appmanifest_*.acf") }, QDir::Files)) {
            const auto manifest = readVdf(apps.filePath(file));
            const VdfNode *state = manifest ? manifest->child(QStringLiteral("AppState")) : nullptr;
            if (state) {
                out.append({ state->valueOf(QStringLiteral("appid")), state->valueOf(QStringLiteral("name")), { } });
            }
        }
    }
    return out;
}

} // namespace

SteamLibrary::SteamLibrary(QString root)
    : m_root(std::move(root))
{
}

QString SteamLibrary::defaultRoot()
{
    return QDir::homePath() + QStringLiteral("/.var/app/com.valvesoftware.Steam/.local/share/Steam");
}

bool SteamLibrary::installed() const
{
    return QFileInfo::exists(m_root + QStringLiteral("/steamapps"));
}

QStringList SteamLibrary::libraries() const
{
    QStringList out { m_root };
    if (const auto folders = readVdf(m_root + QStringLiteral("/steamapps/libraryfolders.vdf"))) {
        if (const VdfNode *list = folders->child(QStringLiteral("libraryfolders"))) {
            for (const VdfNode &entry : list->children) {
                const QString path = entry.block ? entry.valueOf(QStringLiteral("path")) : QString();
                if (!path.isEmpty() && QDir(path).canonicalPath() != QDir(m_root).canonicalPath() && !out.contains(path)) {
                    out.append(path);
                }
            }
        }
    }
    return out;
}

QList<SteamGame> SteamLibrary::games() const
{
    QList<SteamGame> out;
    QStringList seen;
    for (const SteamGame &app : manifests(libraries())) {
        if (app.appId.isEmpty() || app.name.isEmpty() || isTool(app.name) || seen.contains(app.appId)) {
            continue;
        }
        seen.append(app.appId);
        out.append({ app.appId, app.name, artFor(m_root, app.appId) });
    }
    std::sort(out.begin(), out.end(), [](const SteamGame &a, const SteamGame &b) { return a.name.compare(b.name, Qt::CaseInsensitive) < 0; });
    return out;
}

QList<CompatTool> SteamLibrary::compatTools(const QStringList &extensionFolders) const
{
    QList<CompatTool> out;
    // Tools that aren't Steam apps, such as Flathub's GE-Proton, describe themselves in
    // compatibilitytool.vdf.
    QStringList folders = extensionFolders;
    folders.append(m_root + QStringLiteral("/compatibilitytools.d"));
    for (const QString &folder : std::as_const(folders)) {
        QDirIterator it(folder, { QStringLiteral("compatibilitytool.vdf") }, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const auto vdf = readVdf(it.next());
            const VdfNode *tools = vdf ? vdf->find({ QStringLiteral("compatibilitytools"), QStringLiteral("compat_tools") }) : nullptr;
            for (const VdfNode &tool : tools ? tools->children : QList<VdfNode> { }) {
                const QString display = tool.valueOf(QStringLiteral("display_name"));
                if (std::none_of(out.cbegin(), out.cend(), [&tool](const CompatTool &t) { return t.id == tool.key; })) {
                    out.append({ tool.key, display.isEmpty() ? tool.key : display });
                }
            }
        }
    }
    // Valve's Protons are apps: "Proton Experimental" is proton_experimental, "Proton 10.0" proton_10.
    for (const SteamGame &app : manifests(libraries())) {
        static const QRegularExpression proton(QStringLiteral("^Proton (\\d+)\\.\\d+$"));
        if (app.name == QLatin1String("Proton Experimental")) {
            out.append({ QStringLiteral("proton_experimental"), app.name });
        } else if (const auto match = proton.match(app.name); match.hasMatch()) {
            out.append({ QStringLiteral("proton_") + match.captured(1), app.name });
        }
    }
    return out;
}

QString SteamLibrary::configPath() const
{
    return m_root + QStringLiteral("/config/config.vdf");
}

QString SteamLibrary::localConfigPath() const
{
    // The account that used Steam last: the most recently changed localconfig.vdf.
    QString newest;
    QDateTime newestTime;
    const QDir users(m_root + QStringLiteral("/userdata"));
    for (const QString &user : users.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        const QFileInfo info(users.filePath(user + QStringLiteral("/config/localconfig.vdf")));
        if (info.exists() && (newest.isEmpty() || info.lastModified() > newestTime)) {
            newest = info.filePath();
            newestTime = info.lastModified();
        }
    }
    return newest;
}

QString SteamLibrary::compatTool(const QString &appId) const
{
    const auto config = readVdf(configPath());
    const VdfNode *mapping = config ? config->find(compatPath) : nullptr;
    const VdfNode *entry = mapping ? mapping->child(appId) : nullptr;
    return entry ? entry->valueOf(QStringLiteral("name")) : QString();
}

bool SteamLibrary::setCompatTool(const QString &appId, const QString &toolId) const
{
    auto config = readVdf(configPath());
    if (!config) {
        return false;
    }
    VdfNode &mapping = config->ensure(compatPath);
    if (toolId.isEmpty()) {
        mapping.remove(appId);
    } else {
        VdfNode &entry = mapping.ensure({ appId });
        entry.set(QStringLiteral("name"), toolId);
        entry.set(QStringLiteral("config"), QString());
        // 250 is what Steam writes when the user picks a tool for a game.
        entry.set(QStringLiteral("priority"), QStringLiteral("250"));
    }
    return writeVdfFile(configPath(), writeVdf(*config));
}

QString SteamLibrary::launchOptions(const QString &appId) const
{
    const auto config = readVdf(localConfigPath());
    const VdfNode *apps = config ? config->find({ QStringLiteral("UserLocalConfigStore"), QStringLiteral("Software"), QStringLiteral("Valve"),
                                       QStringLiteral("Steam"), QStringLiteral("apps") })
                                 : nullptr;
    const VdfNode *app = apps ? apps->child(appId) : nullptr;
    return app ? app->valueOf(QStringLiteral("LaunchOptions")) : QString();
}

bool SteamLibrary::setLaunchOptions(const QString &appId, const QString &options) const
{
    const QString path = localConfigPath();
    auto config = path.isEmpty() ? std::nullopt : readVdf(path);
    if (!config) {
        return false;
    }
    VdfNode &app = config->ensure({ QStringLiteral("UserLocalConfigStore"), QStringLiteral("Software"), QStringLiteral("Valve"), QStringLiteral("Steam"),
        QStringLiteral("apps"), appId });
    if (options.isEmpty()) {
        app.remove(QStringLiteral("LaunchOptions"));
    } else {
        app.set(QStringLiteral("LaunchOptions"), options);
    }
    return writeVdfFile(path, writeVdf(*config));
}

bool writeVdfFile(const QString &path, const QString &text)
{
    const QString backup = path + QStringLiteral(".orielos-before-game-settings");
    if (!QFileInfo::exists(backup)) {
        QFile::copy(path, backup);
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    file.write(text.toUtf8());
    return file.commit();
}

} // namespace OrielOSGames
