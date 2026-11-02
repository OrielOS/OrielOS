// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "runapp.h"

#include <KLocalizedString>

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QUrl>
#include <QtEndian>

#include <sys/xattr.h>

#include <algorithm>
#include <utility>

namespace OrielOSRunApp {

namespace {

// Words in download names that say how a program is packaged, not what it is.
const QSet<QString> packagingWords = {
    QStringLiteral("setup"),
    QStringLiteral("installer"),
    QStringLiteral("install"),
    QStringLiteral("x64"),
    QStringLiteral("x86"),
    QStringLiteral("win64"),
    QStringLiteral("win32"),
    QStringLiteral("amd64"),
    QStringLiteral("arm64"),
    QStringLiteral("64bit"),
    QStringLiteral("32bit"),
    QStringLiteral("full"),
    QStringLiteral("offline"),
    QStringLiteral("online"),
    QStringLiteral("web"),
    QStringLiteral("latest"),
};

const QSet<QString> installerWords = {
    QStringLiteral("setup"),
    QStringLiteral("installer"),
    QStringLiteral("install"),
};

// The words of a file name without its extension, in lower case: "SteamSetup.exe" gives
// "steam", "setup". A capital starts a new word after a small letter ("SteamSetup") and before a
// small letter that follows capitals ("VLCSetup").
QStringList nameWords(const QString &fileName)
{
    QString base = QFileInfo(fileName).fileName();
    const qsizetype dot = base.lastIndexOf(QLatin1Char('.'));
    if (dot > 0) {
        base.truncate(dot);
    }
    QString spaced;
    for (qsizetype i = 0; i < base.size(); ++i) {
        const QChar c = base.at(i);
        if (i > 0 && c.isUpper()) {
            const QChar before = base.at(i - 1);
            const bool smallFollows = i + 1 < base.size() && base.at(i + 1).isLower();
            if (before.isLower() || (before.isUpper() && smallFollows)) {
                spaced += QLatin1Char(' ');
            }
        }
        spaced += c;
    }
    static const QRegularExpression separators(QStringLiteral("[^a-z0-9]+"));
    return spaced.toLower().split(separators, Qt::SkipEmptyParts);
}

bool isVersion(const QString &word)
{
    static const QRegularExpression version(QStringLiteral("^(v|r|b|build)?[0-9]+[a-z]?$"));
    return version.match(word).hasMatch();
}

// The word without a version joined to its end: four or more digits after a letter, as in 7-Zip's
// "7z2605" (version 26.05), give "7z". Shorter runs belong to the name ("x264", "doom64").
QString withoutJoinedVersion(const QString &word)
{
    static const QRegularExpression joinedVersion(QStringLiteral("(?<=[a-z])[0-9]{4,}$"));
    return QString(word).remove(joinedVersion);
}

QByteArray attribute(const QString &path, const char *name)
{
    const QByteArray file = QFile::encodeName(path);
    const ssize_t size = getxattr(file.constData(), name, nullptr, 0);
    if (size <= 0) {
        return { };
    }
    QByteArray value(size, '\0');
    const ssize_t read = getxattr(file.constData(), name, value.data(), value.size());
    if (read <= 0) {
        return { };
    }
    value.truncate(read);
    return value;
}

// Reading little-endian numbers and strings from a shortcut, refusing anything past its end.
class Reader
{
public:
    explicit Reader(const QByteArray &data)
        : m_data(data)
    {
    }

    std::optional<quint16> u16(qsizetype at) const
    {
        if (at < 0 || at + 2 > m_data.size()) {
            return std::nullopt;
        }
        return qFromLittleEndian<quint16>(m_data.constData() + at);
    }

    std::optional<quint32> u32(qsizetype at) const
    {
        if (at < 0 || at + 4 > m_data.size()) {
            return std::nullopt;
        }
        return qFromLittleEndian<quint32>(m_data.constData() + at);
    }

    // A string of 8-bit characters ending in a zero byte.
    QString ansiz(qsizetype at) const
    {
        if (at < 0 || at >= m_data.size()) {
            return { };
        }
        const qsizetype end = m_data.indexOf('\0', at);
        if (end < 0) {
            return { };
        }
        return QString::fromLatin1(m_data.constData() + at, end - at);
    }

    // A UTF-16 string ending in a zero character.
    QString utf16z(qsizetype at) const
    {
        QString text;
        for (qsizetype i = at;; i += 2) {
            const std::optional<quint16> unit = u16(i);
            if (!unit) {
                return { };
            }
            if (*unit == 0) {
                return text;
            }
            text += QChar(char16_t(*unit));
        }
    }

    // count characters, UTF-16 or 8-bit.
    std::optional<QString> counted(qsizetype at, quint16 count, bool unicode) const
    {
        const qsizetype bytes = unicode ? qsizetype(count) * 2 : count;
        if (at < 0 || at + bytes > m_data.size()) {
            return std::nullopt;
        }
        if (!unicode) {
            return QString::fromLatin1(m_data.constData() + at, count);
        }
        QString text;
        text.reserve(count);
        for (qsizetype i = 0; i < count; ++i) {
            text += QChar(char16_t(*u16(at + i * 2)));
        }
        return text;
    }

private:
    const QByteArray &m_data;
};

// The path as it is on disk: Windows paths ignore case, the Linux file system doesn't, so each
// part that doesn't exist as written is looked up without regard to case. Empty if there's no
// such file.
QString existingPath(const QString &path)
{
    if (QFileInfo::exists(path)) {
        return path;
    }
    QString found = QStringLiteral("/");
    const QStringList parts = path.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        const QString exact = QDir(found).filePath(part);
        if (QFileInfo::exists(exact)) {
            found = exact;
            continue;
        }
        bool matched = false;
        const QStringList entries = QDir(found).entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
        for (const QString &entry : entries) {
            if (entry.compare(part, Qt::CaseInsensitive) == 0) {
                found = QDir(found).filePath(entry);
                matched = true;
                break;
            }
        }
        if (!matched) {
            return { };
        }
    }
    return found;
}

// A file-name-safe word for a program: "My Game.exe" gives "my-game".
QString slug(const QString &text)
{
    static const QRegularExpression separators(QStringLiteral("[^a-z0-9]+"));
    QString result = text.toLower().replace(separators, QStringLiteral("-"));
    while (result.startsWith(QLatin1Char('-'))) {
        result.remove(0, 1);
    }
    while (result.endsWith(QLatin1Char('-'))) {
        result.chop(1);
    }
    return result.isEmpty() ? QStringLiteral("app") : result;
}

// A desktop entry string value on one line, with its backslashes escaped.
QString entryValue(const QString &text)
{
    QString value = text;
    value.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
    value.replace(QLatin1Char('\n'), QStringLiteral("\\n"));
    value.replace(QLatin1Char('\r'), QString());
    return value;
}

} // namespace

QString prefixName(const QString &fileName)
{
    QStringList kept;
    const QStringList words = nameWords(fileName);
    for (const QString &word : words) {
        if (!isVersion(word) && !packagingWords.contains(word)) {
            kept.append(withoutJoinedVersion(word));
        }
    }
    return kept.isEmpty() ? QStringLiteral("app") : kept.join(QLatin1Char('-'));
}

bool looksLikeInstaller(const QString &fileName)
{
    if (fileName.endsWith(QLatin1String(".msi"), Qt::CaseInsensitive)) {
        return true;
    }
    const QStringList words = nameWords(fileName);
    for (const QString &word : words) {
        if (installerWords.contains(word)) {
            return true;
        }
    }
    return false;
}

QString prefixDir(const QString &dataHome, const QString &name)
{
    return QDir(dataHome).filePath(QStringLiteral("orielos/windows-apps/%1/prefix").arg(name));
}

QString logFile(const QString &stateHome, const QString &name)
{
    return QDir(stateHome).filePath(QStringLiteral("orielos/windows-apps/%1.log").arg(name));
}

DownloadSource downloadSource(const QString &filePath)
{
    QByteArray url = attribute(filePath, "user.xdg.origin.url");
    if (url.isEmpty()) {
        url = attribute(filePath, "user.xdg.referrer.url");
    }
    if (url.isEmpty()) {
        return { };
    }
    const QString text = QString::fromUtf8(url);
    return { text, QUrl(text).host() };
}

Command command(const QString &prefix, const QString &filePath, const QStringList &arguments)
{
    Command result;
    result.program = QStringLiteral("umu-run");
    if (filePath.endsWith(QLatin1String(".msi"), Qt::CaseInsensitive)) {
        result.arguments = { QStringLiteral("msiexec"), QStringLiteral("/i"), filePath };
    } else {
        result.arguments = { filePath };
    }
    result.arguments += arguments;
    result.environment = {
        { QStringLiteral("WINEPREFIX"), prefix },
        { QStringLiteral("GAMEID"), QStringLiteral("umu-default") },
        { QStringLiteral("PROTONPATH"), QStringLiteral("GE-Proton") },
        { QStringLiteral("STORE"), QStringLiteral("none") },
    };
    return result;
}

bool needsFirstDownload(const QString &dataHome)
{
    const QDir tools(QDir(dataHome).filePath(QStringLiteral("Steam/compatibilitytools.d")));
    const bool haveProton = !tools.entryList({ QStringLiteral("GE-Proton*") }, QDir::Dirs | QDir::NoDotAndDotDot).isEmpty();
    const bool haveRuntime = QDir(QDir(dataHome).filePath(QStringLiteral("umu"))).exists();
    return !haveProton || !haveRuntime;
}

std::optional<LinkTarget> readShortcut(const QByteArray &data)
{
    // The layout is Microsoft's [MS-SHLLINK]: a 76-byte header, an optional item ID list, an
    // optional LinkInfo block and optional counted strings.
    constexpr quint32 headerSize = 0x4C;
    constexpr quint32 hasIdList = 0x01;
    constexpr quint32 hasLinkInfo = 0x02;
    constexpr quint32 hasName = 0x04;
    constexpr quint32 hasRelativePath = 0x08;
    constexpr quint32 hasWorkingDir = 0x10;
    constexpr quint32 hasArguments = 0x20;
    constexpr quint32 isUnicode = 0x80;
    constexpr quint32 volumeIdAndLocalBasePath = 0x01;

    const Reader read(data);
    if (read.u32(0) != headerSize) {
        return std::nullopt;
    }
    const std::optional<quint32> flags = read.u32(0x14);
    if (!flags) {
        return std::nullopt;
    }
    qsizetype at = headerSize;
    if (*flags & hasIdList) {
        const std::optional<quint16> size = read.u16(at);
        if (!size) {
            return std::nullopt;
        }
        at += 2 + *size;
    }

    LinkTarget target;
    if (*flags & hasLinkInfo) {
        const std::optional<quint32> size = read.u32(at);
        const std::optional<quint32> infoHeaderSize = read.u32(at + 4);
        const std::optional<quint32> infoFlags = read.u32(at + 8);
        if (!size || !infoHeaderSize || !infoFlags || *size < 0x1C || at + *size > data.size()) {
            return std::nullopt;
        }
        if (*infoFlags & volumeIdAndLocalBasePath) {
            QString base;
            QString suffix;
            if (*infoHeaderSize >= 0x24) {
                const quint32 baseUnicode = read.u32(at + 28).value_or(0);
                const quint32 suffixUnicode = read.u32(at + 32).value_or(0);
                if (baseUnicode) {
                    base = read.utf16z(at + baseUnicode);
                }
                if (suffixUnicode) {
                    suffix = read.utf16z(at + suffixUnicode);
                }
            }
            if (base.isEmpty()) {
                const quint32 offset = read.u32(at + 16).value_or(0);
                if (offset) {
                    base = read.ansiz(at + offset);
                }
            }
            if (suffix.isEmpty()) {
                const quint32 offset = read.u32(at + 24).value_or(0);
                if (offset) {
                    suffix = read.ansiz(at + offset);
                }
            }
            target.windowsPath = base;
            if (!suffix.isEmpty()) {
                if (!target.windowsPath.endsWith(QLatin1Char('\\'))) {
                    target.windowsPath += QLatin1Char('\\');
                }
                target.windowsPath += suffix;
            }
        }
        at += *size;
    }

    const bool unicode = *flags & isUnicode;
    auto nextString = [&]() -> std::optional<QString> {
        const std::optional<quint16> count = read.u16(at);
        if (!count) {
            return std::nullopt;
        }
        const std::optional<QString> text = read.counted(at + 2, *count, unicode);
        if (!text) {
            return std::nullopt;
        }
        at += 2 + (unicode ? qsizetype(*count) * 2 : *count);
        return text;
    };
    if (*flags & hasName && !nextString()) {
        return std::nullopt;
    }
    if (*flags & hasRelativePath) {
        const std::optional<QString> text = nextString();
        if (!text) {
            return std::nullopt;
        }
        target.relativePath = *text;
    }
    if (*flags & hasWorkingDir && !nextString()) {
        return std::nullopt;
    }
    if (*flags & hasArguments) {
        const std::optional<QString> text = nextString();
        if (!text) {
            return std::nullopt;
        }
        target.arguments = *text;
    }
    if (target.windowsPath.isEmpty() && target.relativePath.isEmpty()) {
        return std::nullopt;
    }
    return target;
}

QString linuxPath(const QString &prefix, const QString &windowsPath)
{
    QString path = windowsPath;
    path.replace(QLatin1Char('\\'), QLatin1Char('/'));
    if (path.size() < 2 || path.at(1) != QLatin1Char(':') || !path.at(0).isLetter()) {
        return { };
    }
    const QChar drive = path.at(0).toLower();
    const QString rest = path.mid(2);
    if (drive == QLatin1Char('z')) {
        return QDir::cleanPath(rest.isEmpty() ? QStringLiteral("/") : rest);
    }
    return QDir::cleanPath(prefix + QStringLiteral("/drive_") + drive + QLatin1Char('/') + rest);
}

QStringList splitArguments(const QString &arguments)
{
    QStringList result;
    QString current;
    bool inQuotes = false;
    bool haveArgument = false;
    for (qsizetype i = 0; i < arguments.size(); ++i) {
        const QChar c = arguments.at(i);
        if (c == QLatin1Char('\\') && i + 1 < arguments.size() && arguments.at(i + 1) == QLatin1Char('"')) {
            current += QLatin1Char('"');
            haveArgument = true;
            ++i;
        } else if (c == QLatin1Char('"')) {
            inQuotes = !inQuotes;
            haveArgument = true;
        } else if (c.isSpace() && !inQuotes) {
            if (haveArgument) {
                result.append(current);
                current.clear();
                haveArgument = false;
            }
        } else {
            current += c;
            haveArgument = true;
        }
    }
    if (haveArgument) {
        result.append(current);
    }
    return result;
}

QList<Shortcut> findShortcuts(const QString &prefix)
{
    const QString startMenu = QStringLiteral("Microsoft/Windows/Start Menu/Programs");
    QStringList menus = { QDir(prefix).filePath(QStringLiteral("drive_c/ProgramData/") + startMenu) };
    QStringList desktops;
    const QDir users(QDir(prefix).filePath(QStringLiteral("drive_c/users")));
    const QStringList userNames = users.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &user : userNames) {
        menus.append(users.filePath(user + QStringLiteral("/AppData/Roaming/") + startMenu));
        desktops.append(users.filePath(user + QStringLiteral("/Desktop")));
    }

    QStringList links;
    for (const QString &menu : std::as_const(menus)) {
        QDirIterator it(menu, { QStringLiteral("*.lnk") }, QDir::Files, QDirIterator::Subdirectories);
        QStringList found;
        while (it.hasNext()) {
            found.append(it.next());
        }
        found.sort();
        links += found;
    }
    for (const QString &desktop : std::as_const(desktops)) {
        const QDir dir(desktop);
        const QStringList found = dir.entryList({ QStringLiteral("*.lnk") }, QDir::Files, QDir::Name);
        for (const QString &name : found) {
            links.append(dir.filePath(name));
        }
    }

    QList<Shortcut> shortcuts;
    QSet<QString> seen;
    for (const QString &link : std::as_const(links)) {
        QFile file(link);
        if (!file.open(QIODevice::ReadOnly)) {
            continue;
        }
        const std::optional<LinkTarget> target = readShortcut(file.read(1024 * 1024));
        if (!target) {
            continue;
        }
        QString path;
        if (!target->windowsPath.isEmpty()) {
            path = linuxPath(prefix, target->windowsPath);
        } else {
            path = QDir::cleanPath(
                QFileInfo(link).absolutePath() + QLatin1Char('/') + QString(target->relativePath).replace(QLatin1Char('\\'), QLatin1Char('/')));
        }
        path = path.isEmpty() ? QString() : existingPath(path);
        const QString name = QFileInfo(link).completeBaseName();
        if (path.isEmpty() || !path.endsWith(QLatin1String(".exe"), Qt::CaseInsensitive) || name.contains(QLatin1String("uninstall"), Qt::CaseInsensitive)
            || QFileInfo(path).fileName().contains(QLatin1String("unins"), Qt::CaseInsensitive) || seen.contains(path)) {
            continue;
        }
        seen.insert(path);
        shortcuts.append({ name, path, splitArguments(target->arguments) });
    }
    return shortcuts;
}

QString execArgument(const QString &argument)
{
    static const QString reserved = QStringLiteral(" \t\n\"'\\><~|&;$*?#()`");
    bool quote = argument.isEmpty();
    for (const QChar c : argument) {
        if (reserved.contains(c)) {
            quote = true;
            break;
        }
    }
    QString result;
    if (quote) {
        result = QLatin1Char('"');
        for (const QChar c : argument) {
            if (c == QLatin1Char('"') || c == QLatin1Char('`') || c == QLatin1Char('$') || c == QLatin1Char('\\')) {
                result += QLatin1Char('\\');
            }
            result += c;
        }
        result += QLatin1Char('"');
    } else {
        result = argument;
    }
    result.replace(QLatin1Char('%'), QStringLiteral("%%"));
    // The quoting rule applies after the string escape, which writes a backslash as two.
    result.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
    return result;
}

QString writeStartEntry(const QString &applicationsDir, const QString &name, const Shortcut &shortcut)
{
    QStringList exec = { QStringLiteral("orielos-run-app"), QStringLiteral("--launch"), execArgument(name), execArgument(shortcut.target) };
    for (const QString &argument : shortcut.arguments) {
        exec.append(execArgument(argument));
    }
    const QString path
        = QDir(applicationsDir).filePath(QStringLiteral("orielos-windows-%1-%2.desktop").arg(slug(name), slug(QFileInfo(shortcut.target).completeBaseName())));
    QDir().mkpath(applicationsDir);
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        return { };
    }
    const QString entry = QStringLiteral("[Desktop Entry]\n"
                                         "Type=Application\n"
                                         "Name=%1\n"
                                         "Comment=%2\n"
                                         "Exec=%3\n"
                                         "Icon=application-x-ms-dos-executable\n"
                                         "Categories=Wine;X-OrielOS-WindowsApp;\n"
                                         "X-OrielOS-WindowsPrefix=%4\n")
                              .arg(entryValue(shortcut.name), entryValue(i18nc("@info a Start entry's description", "Windows program")),
                                  exec.join(QLatin1Char(' ')), entryValue(name));
    file.write(entry.toUtf8());
    if (!file.commit()) {
        return { };
    }
    return path;
}

std::optional<KnownApp> knownApp(const QByteArray &list, const QString &fileName)
{
    const QString suffix = QFileInfo(fileName).suffix().toLower();
    const bool packageFile
        = suffix == QLatin1String("msix") || suffix == QLatin1String("msixbundle") || suffix == QLatin1String("appx") || suffix == QLatin1String("appxbundle");
    const QString name = prefixName(fileName);
    const QJsonArray apps = QJsonDocument::fromJson(list).object().value(QLatin1String("apps")).toArray();
    for (const QJsonValue &value : apps) {
        const QJsonObject app = value.toObject();
        const QJsonArray names = app.value(QLatin1String("names")).toArray();
        const bool matches = std::any_of(names.begin(), names.end(), [&name](const QJsonValue &known) {
            const QString key = known.toString();
            return !key.isEmpty() && (name == key || name.startsWith(key + QLatin1Char('-')));
        });
        if (matches) {
            KnownApp known;
            known.name = app.value(QLatin1String("name")).toString();
            known.store = app.value(QLatin1String("store")).toString();
            known.launcher = app.value(QLatin1String("launcher")).toBool();
            known.note = app.value(QLatin1String("note")).toString();
            known.package = packageFile || app.value(QLatin1String("package")).toBool();
            known.alternative = app.value(QLatin1String("alternative")).toString();
            return known;
        }
    }
    if (packageFile) {
        KnownApp known;
        known.package = true;
        return known;
    }
    return std::nullopt;
}

QByteArray knownAppsList(const QString &fetchedPath, const QString &bundledPath)
{
    const auto read = [](const QString &path) -> std::pair<QByteArray, int> {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
            return { { }, -1 };
        }
        const QByteArray data = file.readAll();
        const QJsonObject object = QJsonDocument::fromJson(data).object();
        if (!object.value(QLatin1String("apps")).isArray()) {
            return { { }, -1 };
        }
        return { data, object.value(QLatin1String("version")).toInt(0) };
    };
    const auto bundled = read(bundledPath);
    const auto fetched = read(fetchedPath);
    return fetched.second >= 0 && fetched.second >= bundled.second ? fetched.first : bundled.first;
}

} // namespace OrielOSRunApp
