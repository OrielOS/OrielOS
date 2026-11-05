// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "aboutinfo.h"

#include <KLocalizedString>

#include <QClipboard>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QLocale>
#include <QPointer>
#include <QRegularExpression>
#include <QSysInfo>
#include <QTextStream>

namespace OrielOSSettingsPages {

namespace {

const QString service = QStringLiteral("org.freedesktop.hostname1");
const QString path = QStringLiteral("/org/freedesktop/hostname1");
const QString interface = QStringLiteral("org.freedesktop.hostname1");
const QString propertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");

// The longest name hostnamed takes as a static name.
constexpr int maxNameLength = 63;
// The password prompt waits for the person; D-Bus's own 25 seconds would end the call first.
constexpr int renameTimeout = 10 * 60 * 1000;

QString readTrimmed(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return { };
    }
    return QString::fromUtf8(file.readAll()).trimmed();
}

QStringList readLines(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return { };
    }
    return QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'));
}

// hostname1's three names, read in one call. Without hostnamed, the kernel's name.
void readHostnamed(std::function<void(const QVariantMap &names)> done)
{
    QDBusMessage message = QDBusMessage::createMethodCall(service, path, propertiesInterface, QStringLiteral("GetAll"));
    message << interface;
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message));
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, watcher, [watcher, done]() {
        watcher->deleteLater();
        const QDBusPendingReply<QVariantMap> reply = *watcher;
        done(reply.isError() ? QVariantMap { { QStringLiteral("Hostname"), QSysInfo::machineHostName() } } : reply.value());
    });
}

// SetStaticHostname or SetPrettyHostname, with interactive true so polkit can ask for a password.
void setHostnamed(const QString &method, const QString &name, std::function<void(const QString &errorName, const QString &errorMessage)> done)
{
    QDBusMessage message = QDBusMessage::createMethodCall(service, path, interface, method);
    message << name << true;
    message.setInteractiveAuthorizationAllowed(true);
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message, renameTimeout));
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, watcher, [watcher, done]() {
        watcher->deleteLater();
        const QDBusPendingReply<> reply = *watcher;
        if (reply.isError()) {
            done(reply.error().name(), reply.error().message());
        } else {
            done({ }, { });
        }
    });
}

void copyToClipboard(const QString &text)
{
    QGuiApplication::clipboard()->setText(text);
}

// The processor's name from /proc/cpuinfo, with the number of logical processors (threads).
QString readProcessor(const QString &cpuinfoPath)
{
    QString name;
    int threads = 0;
    const QStringList lines = readLines(cpuinfoPath);
    for (const QString &line : lines) {
        const qsizetype colon = line.indexOf(QLatin1Char(':'));
        if (colon < 0) {
            continue;
        }
        const QString key = line.left(colon).trimmed();
        if (key == QLatin1String("processor")) {
            ++threads;
        } else if (key == QLatin1String("model name") && name.isEmpty()) {
            name = line.mid(colon + 1);
        }
    }
    // "Intel(R) Core(TM) i7-14700K" reads better as "Intel Core i7-14700K".
    static const QRegularExpression marks(QStringLiteral("\\((R|TM)\\)"), QRegularExpression::CaseInsensitiveOption);
    name = name.remove(marks).simplified();
    if (name.isEmpty()) {
        return { };
    }
    if (threads == 0) {
        return name;
    }
    return i18ncp("@info %2 is a processor, such as AMD Ryzen 7 7840HS", "%2 (%1 thread)", "%2 (%1 threads)", threads, name);
}

// MemTotal from /proc/meminfo: what the system can use, a little less than what is fitted.
QString readMemory(const QString &meminfoPath)
{
    const QStringList lines = readLines(meminfoPath);
    for (const QString &line : lines) {
        if (!line.startsWith(QLatin1String("MemTotal:"))) {
            continue;
        }
        // "MemTotal:       16255620 kB", where kB is 1024 bytes.
        const qint64 kibibytes = line.section(QLatin1Char(':'), 1).simplified().section(QLatin1Char(' '), 0, 0).toLongLong();
        if (kibibytes <= 0) {
            return { };
        }
        const QLocale locale;
        return i18nc(
            "@info %1 is an amount of memory, such as 15.5 GB", "%1 usable", locale.formattedDataSize(kibibytes * 1024, 1, QLocale::DataSizeTraditionalFormat));
    }
    return { };
}

// "0x10de" becomes "10de".
QString hexId(const QString &path)
{
    QString id = readTrimmed(path).toLower();
    if (id.startsWith(QLatin1String("0x"))) {
        id = id.mid(2);
    }
    return id;
}

struct PciNames
{
    QString vendor;
    QString device;
};

// The vendor's and device's names in pci.ids: vendor lines at the start of a line, their devices
// after one tab, subsystems after two, and the class list from the first "C " line on.
PciNames lookUp(const QString &idsPath, const QString &vendor, const QString &device)
{
    PciNames names;
    QFile file(idsPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return names;
    }
    QTextStream in(&file);
    bool inVendor = false;
    QString line;
    while (in.readLineInto(&line)) {
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
            continue;
        }
        if (line.startsWith(QLatin1String("C "))) {
            break;
        }
        if (!line.startsWith(QLatin1Char('\t'))) {
            if (inVendor) {
                break;
            }
            if (line.startsWith(vendor + QLatin1String("  "))) {
                inVendor = true;
                names.vendor = line.mid(vendor.size() + 2).trimmed();
            }
            continue;
        }
        if (inVendor && !line.startsWith(QLatin1String("\t\t")) && line.mid(1).startsWith(device + QLatin1String("  "))) {
            names.device = line.mid(device.size() + 3).trimmed();
            break;
        }
    }
    return names;
}

QString shortVendor(const QString &name)
{
    if (name == QLatin1String("NVIDIA Corporation")) {
        return QStringLiteral("NVIDIA");
    }
    if (name.startsWith(QLatin1String("Advanced Micro Devices"))) {
        return QStringLiteral("AMD");
    }
    if (name == QLatin1String("Intel Corporation")) {
        return QStringLiteral("Intel");
    }
    return name;
}

// The marketing name in the last brackets, when there is one: "AD107M [GeForce RTX 4050 Max-Q / Mobile]".
QString model(const QString &device)
{
    static const QRegularExpression bracketed(QStringLiteral("\\[([^\\]]+)\\][^\\[]*$"));
    const QRegularExpressionMatch match = bracketed.match(device);
    return match.hasMatch() ? match.captured(1).trimmed() : device;
}

// Every display controller (PCI class 0x03), in the order of their addresses.
QStringList readGraphics(const QString &sysRoot, const QString &idsPath)
{
    QStringList cards;
    // The devices are links into the device tree, so links count.
    const QDir devices(sysRoot + QStringLiteral("/bus/pci/devices"));
    const QStringList entries = devices.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System, QDir::Name);
    for (const QString &entry : entries) {
        const QString card = devices.filePath(entry);
        if (!readTrimmed(card + QStringLiteral("/class")).startsWith(QLatin1String("0x03"))) {
            continue;
        }
        const QString vendorId = hexId(card + QStringLiteral("/vendor"));
        const QString deviceId = hexId(card + QStringLiteral("/device"));
        const PciNames names = lookUp(idsPath, vendorId, deviceId);
        const QString maker = shortVendor(names.vendor);
        if (maker.isEmpty()) {
            cards.append(i18nc("@info %1 and %2 are PCI ids, such as 10de and 28e1", "Vendor %1, device %2", vendorId, deviceId));
        } else if (names.device.isEmpty()) {
            cards.append(i18nc("@info %1 is a maker such as NVIDIA, %2 a PCI id such as 28e1", "%1, device %2", maker, deviceId));
        } else {
            const QString name = model(names.device);
            cards.append(name.startsWith(maker) ? name : QString(maker + QLatin1Char(' ') + name));
        }
    }
    return cards;
}

// What firmware writes in DMI fields it wasn't given.
bool isPlaceholder(const QString &value)
{
    static const QStringList placeholders {
        QStringLiteral("to be filled by o.e.m."),
        QStringLiteral("default string"),
        QStringLiteral("system product name"),
        QStringLiteral("system manufacturer"),
        QStringLiteral("system version"),
        QStringLiteral("not applicable"),
        QStringLiteral("not specified"),
        QStringLiteral("none"),
        QStringLiteral("o.e.m."),
        QStringLiteral("oem"),
        QStringLiteral("unknown"),
        QStringLiteral("invalid"),
        QStringLiteral("type1productconfigid"),
        QStringLiteral("0123456789"),
        QStringLiteral("123456789"),
    };
    const QString lower = value.simplified().toLower();
    return lower.isEmpty() || placeholders.contains(lower);
}

// The maker and model from DMI. Desktop PCs built from parts often leave the system's fields as
// placeholders; the motherboard's maker and model say more then.
QString readDevice(const QString &sysRoot)
{
    const QString dmi = sysRoot + QStringLiteral("/class/dmi/id/");
    QString vendor = readTrimmed(dmi + QStringLiteral("sys_vendor"));
    QString product = readTrimmed(dmi + QStringLiteral("product_name"));
    // Lenovo keeps a part number in product_name and the model's name in product_version.
    if (vendor.compare(QLatin1String("LENOVO"), Qt::CaseInsensitive) == 0) {
        const QString version = readTrimmed(dmi + QStringLiteral("product_version"));
        if (!isPlaceholder(version)) {
            product = version;
        }
    }
    if (isPlaceholder(product)) {
        vendor = readTrimmed(dmi + QStringLiteral("board_vendor"));
        product = readTrimmed(dmi + QStringLiteral("board_name"));
    }
    vendor = isPlaceholder(vendor) ? QString() : vendor.simplified();
    product = isPlaceholder(product) ? QString() : product.simplified();
    if (vendor.isEmpty() || product.isEmpty()) {
        return product.isEmpty() ? vendor : product;
    }
    return product.startsWith(vendor, Qt::CaseInsensitive) ? product : QString(vendor + QLatin1Char(' ') + product);
}

QString readSystemType()
{
    const QString architecture = QSysInfo::currentCpuArchitecture();
    QString name = architecture;
    if (architecture == QLatin1String("x86_64")) {
        name = QStringLiteral("x86-64");
    } else if (architecture == QLatin1String("arm64")) {
        name = QStringLiteral("ARM64");
    }
    return i18nc("@info %1 is 64 or 32, %2 a kind of processor such as x86-64", "%1-bit, %2 processor", int(QSysInfo::WordSize), name);
}

// VERSION from os-release, without its quotes.
QString osReleaseVersion(const QString &osReleasePath)
{
    const QStringList lines = readLines(osReleasePath);
    for (const QString &line : lines) {
        if (line.startsWith(QLatin1String("VERSION="))) {
            QString value = line.mid(8).trimmed();
            if (value.size() >= 2 && (value.startsWith(QLatin1Char('"')) || value.startsWith(QLatin1Char('\''))) && value.endsWith(value.at(0))) {
                value = value.mid(1, value.size() - 2);
            }
            return value;
        }
    }
    return { };
}

QVariantMap row(const QString &label, const QString &value)
{
    return { { QStringLiteral("label"), label }, { QStringLiteral("value"), value } };
}

QString textOf(const QVariantList &rows)
{
    QStringList lines;
    for (const QVariant &item : rows) {
        const QVariantMap row = item.toMap();
        lines.append(row.value(QStringLiteral("label")).toString() + QStringLiteral(": ") + row.value(QStringLiteral("value")).toString());
    }
    return lines.join(QLatin1Char('\n'));
}

} // namespace

AboutInfo::AboutInfo(QObject *parent)
    : AboutInfo(Environment { QStringLiteral("/proc"), QStringLiteral("/sys"), QStringLiteral("/usr/lib/os-release"),
                    QStringLiteral("/usr/share/hwdata/pci.ids"), readHostnamed, setHostnamed, copyToClipboard },
          parent)
{
}

AboutInfo::AboutInfo(Environment environment, QObject *parent)
    : QObject(parent)
    , m_environment(std::move(environment))
{
    reload();
}

void AboutInfo::reload()
{
    m_processor = readProcessor(m_environment.procRoot + QStringLiteral("/cpuinfo"));
    m_memory = readMemory(m_environment.procRoot + QStringLiteral("/meminfo"));
    m_graphics = readGraphics(m_environment.sysRoot, m_environment.pciIdsPath);
    m_device = readDevice(m_environment.sysRoot);
    m_systemType = readSystemType();
    m_version = osReleaseVersion(m_environment.osReleasePath);
    m_kernel = readTrimmed(m_environment.procRoot + QStringLiteral("/sys/kernel/osrelease"));
    if (m_kernel.isEmpty()) {
        m_kernel = QSysInfo::kernelVersion();
    }
    // Plasma names only its major version in the session; that's enough here.
    const QString plasma = qEnvironmentVariable("KDE_SESSION_VERSION");
    m_desktop
        = plasma.isEmpty() ? i18nc("@info The desktop", "KDE Plasma") : i18nc("@info The desktop, %1 is its major version, such as 6", "KDE Plasma %1", plasma);
    Q_EMIT changed();
    readNames();
}

void AboutInfo::readNames()
{
    m_environment.readNames([self = QPointer<AboutInfo>(this)](const QVariantMap &names) {
        if (self) {
            self->setNames(names);
        }
    });
}

void AboutInfo::setNames(const QVariantMap &names)
{
    for (const auto *key : { "PrettyHostname", "StaticHostname", "Hostname" }) {
        const QString name = names.value(QLatin1String(key)).toString().trimmed();
        if (!name.isEmpty()) {
            m_name = name;
            break;
        }
    }
    Q_EMIT changed();
}

QVariantList AboutInfo::deviceSpecs() const
{
    QVariantList rows;
    const auto add = [&rows](const QString &label, const QString &value) {
        if (!value.isEmpty()) {
            rows.append(row(label, value));
        }
    };
    add(i18nc("@label", "Device name"), m_name);
    add(i18nc("@label", "Processor"), m_processor);
    add(i18nc("@label", "Installed memory"), m_memory);
    for (const QString &card : m_graphics) {
        add(i18nc("@label A graphics card", "Graphics"), card);
    }
    add(i18nc("@label The PC's maker and model", "Device"), m_device);
    add(i18nc("@label", "System type"), m_systemType);
    return rows;
}

QVariantList AboutInfo::orielOSSpecs() const
{
    QVariantList rows;
    if (!m_version.isEmpty()) {
        rows.append(row(i18nc("@label OrielOS's version", "Version"), m_version));
    }
    rows.append(row(i18nc("@label", "Kernel"), m_kernel));
    rows.append(row(i18nc("@label", "Desktop"), m_desktop));
    return rows;
}

QString AboutInfo::validate(const QString &name) const
{
    if (name.isEmpty()) {
        return i18nc("@info", "Enter a name.");
    }
    if (name.size() > maxNameLength) {
        return i18nc("@info %1 is a number", "Use up to %1 characters.", maxNameLength);
    }
    for (qsizetype i = 0; i < name.size(); ++i) {
        const QChar c = name.at(i);
        const char16_t u = c.unicode();
        if ((u >= u'a' && u <= u'z') || (u >= u'A' && u <= u'Z') || (u >= u'0' && u <= u'9') || u == u'-') {
            continue;
        }
        if (c.isSpace()) {
            return i18nc("@info", "Spaces can't be used. Try a hyphen instead.");
        }
        // An emoji, for one, is two halves.
        const QString character = name.mid(i, c.isHighSurrogate() ? 2 : 1);
        return i18nc("@info %1 is a character", "“%1” can't be used. Use only letters A to Z, numbers and hyphens.", character);
    }
    if (name.startsWith(QLatin1Char('-')) || name.endsWith(QLatin1Char('-'))) {
        return i18nc("@info", "The name can't start or end with a hyphen.");
    }
    return { };
}

void AboutInfo::rename(const QString &name)
{
    if (m_renaming) {
        return;
    }
    const QString problem = validate(name);
    if (!problem.isEmpty()) {
        showMessage(problem, true);
        return;
    }
    m_renaming = true;
    m_message.clear();
    m_messageIsError = false;
    Q_EMIT changed();
    // The static name is the one the network and other PCs see; the pretty name is the one shown.
    // The rename goes on if the page closes meanwhile.
    m_environment.setName(
        QStringLiteral("SetStaticHostname"), name, [self = QPointer<AboutInfo>(this), name](const QString &errorName, const QString &errorMessage) {
            if (!self) {
                return;
            }
            if (!errorName.isEmpty()) {
                self->renameFailed(errorName, errorMessage, false);
                return;
            }
            self->m_environment.setName(QStringLiteral("SetPrettyHostname"), name, [self, name](const QString &errorName, const QString &errorMessage) {
                if (!self) {
                    return;
                }
                if (!errorName.isEmpty()) {
                    self->renameFailed(errorName, errorMessage, true);
                    return;
                }
                self->m_renaming = false;
                self->m_name = name;
                self->showMessage(i18nc("@info %1 is the PC's new name", "This PC is now called %1.", name), false);
                Q_EMIT self->renamed();
            });
        });
}

void AboutInfo::renameFailed(const QString &errorName, const QString &errorMessage, bool staticNameChanged)
{
    m_renaming = false;
    // polkit's prompt was dismissed, the password was wrong, or there's no one to ask.
    if (errorName == QLatin1String("org.freedesktop.DBus.Error.AccessDenied")
        || errorName == QLatin1String("org.freedesktop.DBus.Error.InteractiveAuthorizationRequired")) {
        showMessage(i18nc("@info", "This PC's name wasn't changed: permission wasn't given."), true);
    } else {
        showMessage(i18nc("@info %1 is the reason", "This PC's name couldn't be changed: %1", errorMessage.isEmpty() ? errorName : errorMessage), true);
    }
    // Half done, the name shown may have changed too; hostnamed knows what it is now.
    if (staticNameChanged) {
        readNames();
    }
}

void AboutInfo::showMessage(const QString &message, bool isError)
{
    m_message = message;
    m_messageIsError = isError;
    Q_EMIT changed();
}

void AboutInfo::copyDevice()
{
    if (m_environment.copy) {
        m_environment.copy(textOf(deviceSpecs()));
    }
}

void AboutInfo::copyOrielOS()
{
    if (m_environment.copy) {
        m_environment.copy(textOf(orielOSSpecs()));
    }
}

} // namespace OrielOSSettingsPages
