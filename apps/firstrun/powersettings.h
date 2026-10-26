// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QVariantList>
#include <qqmlintegration.h>

// The first-run setup's power choices: whether the computer sleeps when it isn't being used and
// after how many minutes, and after how many minutes the screen turns off (0 for never). save()
// hands them to first-run-power through pkexec, which writes them to /etc/xdg/powerdevilrc, the
// settings every new user starts with. The page starts from PowerDevil's own defaults on mains
// power, so nothing is written until a choice changes.
class PowerSettings : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool sleepWhenIdle READ sleepWhenIdle WRITE setSleepWhenIdle NOTIFY settingsChanged)
    Q_PROPERTY(int sleepAfterMinutes READ sleepAfterMinutes WRITE setSleepAfterMinutes NOTIFY settingsChanged)
    Q_PROPERTY(int screenOffAfterMinutes READ screenOffAfterMinutes WRITE setScreenOffAfterMinutes NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList sleepChoices READ sleepChoices CONSTANT)
    Q_PROPERTY(QVariantList screenOffChoices READ screenOffChoices CONSTANT)
    Q_PROPERTY(bool saving READ saving NOTIFY savingChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    // PowerDevil's defaults on mains power.
    static constexpr int defaultSleepAfterMinutes = 15;
    static constexpr int defaultScreenOffAfterMinutes = 10;
    // The longest wait the helper accepts: a day.
    static constexpr int maxMinutes = 1440;

    explicit PowerSettings(QObject *parent = nullptr);
    ~PowerSettings() override;

    bool sleepWhenIdle() const;
    void setSleepWhenIdle(bool sleep);
    int sleepAfterMinutes() const;
    void setSleepAfterMinutes(int minutes);
    int screenOffAfterMinutes() const;
    void setScreenOffAfterMinutes(int minutes);

    // The choices the page offers, as { text, minutes } maps; the screen's list ends with Never (0).
    QVariantList sleepChoices() const;
    QVariantList screenOffChoices() const;

    bool saving() const;
    QString error() const;

    // first-run-power's arguments for the current choices: the minutes before sleeping and before
    // the screen turns off, each 0 for never.
    QStringList helperArguments() const;

    // Save the choices if they differ from the last ones saved, or from the defaults before the
    // first save. A call while a save runs saves again once it ends, with the choices then.
    Q_INVOKABLE void save();

    // Run program with arguments, then the helper's arguments, instead of pkexec first-run-power.
    // For the unit tests.
    void setCommandForTesting(const QString &program, const QStringList &arguments);

Q_SIGNALS:
    void settingsChanged();
    void savingChanged();
    void errorChanged();
    void saved(bool ok);

private:
    void setError(const QString &error);
    void finish(bool ok);

    bool m_sleepWhenIdle = true;
    int m_sleepAfterMinutes = defaultSleepAfterMinutes;
    int m_screenOffAfterMinutes = defaultScreenOffAfterMinutes;
    QStringList m_lastSaved;
    QStringList m_running;
    bool m_saveAgain = false;
    QProcess *m_process = nullptr;
    QString m_program;
    QStringList m_arguments;
    QString m_error;
};
