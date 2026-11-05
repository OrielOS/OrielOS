// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <qqmlintegration.h>

#include <functional>

namespace OrielOSSettingsPages {

// Settings › System › About: what this PC is called, which it can change through systemd-hostnamed,
// and what the PC and OrielOS are, read from /proc, sysfs, hwdata's pci.ids and os-release. Needs no
// root to read; renaming asks polkit. Every string is ready to show.
class AboutInfo : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // hostnamed's pretty name, else its static name, else the kernel's.
    Q_PROPERTY(QString name READ name NOTIFY changed)
    // The maker and model, such as "LENOVO Legion Slim 5 16APH8", or empty when the firmware doesn't
    // say.
    Q_PROPERTY(QString device READ device NOTIFY changed)
    // { label, value } for each row of the two cards. A PC with two graphics cards has two Graphics
    // rows.
    Q_PROPERTY(QVariantList deviceSpecs READ deviceSpecs NOTIFY changed)
    Q_PROPERTY(QVariantList orielOSSpecs READ orielOSSpecs NOTIFY changed)
    // A rename is waiting for hostnamed, and for polkit's password prompt.
    Q_PROPERTY(bool renaming READ isRenaming NOTIFY changed)
    // What the last rename did, or why a name can't be used. Empty otherwise.
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(bool messageIsError READ messageIsError NOTIFY changed)

public:
    struct Environment
    {
        QString procRoot;
        QString sysRoot;
        QString osReleasePath;
        QString pciIdsPath;
        // Reads hostname1's PrettyHostname, StaticHostname and Hostname and calls done with them.
        std::function<void(std::function<void(const QVariantMap &names)> done)> readNames;
        // Calls hostname1's SetStaticHostname or SetPrettyHostname with this name, letting polkit ask
        // for an administrator's password, then done with the D-Bus error's name and message, both
        // empty when it worked.
        std::function<void(const QString &method, const QString &name, std::function<void(const QString &errorName, const QString &errorMessage)> done)>
            setName;
        // Puts this text on the clipboard.
        std::function<void(const QString &text)> copy;
    };

    // The real /proc, /sys, os-release, pci.ids, hostnamed and clipboard.
    explicit AboutInfo(QObject *parent = nullptr);
    AboutInfo(Environment environment, QObject *parent);

    QString name() const { return m_name; }
    QString device() const { return m_device; }
    QVariantList deviceSpecs() const;
    QVariantList orielOSSpecs() const;
    bool isRenaming() const { return m_renaming; }
    QString message() const { return m_message; }
    bool messageIsError() const { return m_messageIsError; }

    // Why this name can't be used, or empty when it can: 1 to 63 letters A to Z, numbers and
    // hyphens, not starting or ending with a hyphen.
    Q_INVOKABLE QString validate(const QString &name) const;
    // Give this PC a new name. It takes effect at once; nothing needs a restart.
    Q_INVOKABLE void rename(const QString &name);
    // Each card as text, one "Label: value" line for each row.
    Q_INVOKABLE void copyDevice();
    Q_INVOKABLE void copyOrielOS();
    Q_INVOKABLE void reload();

Q_SIGNALS:
    void changed();
    // A rename worked.
    void renamed();

private:
    void readNames();
    void setNames(const QVariantMap &names);
    void renameFailed(const QString &errorName, const QString &errorMessage, bool staticNameChanged);
    void showMessage(const QString &message, bool isError);

    Environment m_environment;
    QString m_name;
    QString m_device;
    QString m_processor;
    QString m_memory;
    QStringList m_graphics;
    QString m_systemType;
    QString m_version;
    QString m_kernel;
    QString m_desktop;
    bool m_renaming = false;
    QString m_message;
    bool m_messageIsError = false;
};

} // namespace OrielOSSettingsPages
