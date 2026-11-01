// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <qqmlintegration.h>

// The first-run setup's privacy choice: whether location services are on. save() hands it to
// first-run-privacy through pkexec, which turns GeoClue's location sources off for the whole
// computer, or back on. Location starts on, as GeoClue's own settings have it, so nothing is
// written unless it's turned off.
class PrivacySettings : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool location READ location WRITE setLocation NOTIFY settingsChanged)
    Q_PROPERTY(bool saving READ saving NOTIFY savingChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit PrivacySettings(QObject *parent = nullptr);
    ~PrivacySettings() override;

    bool location() const { return m_location; }
    void setLocation(bool on);
    bool saving() const { return m_process != nullptr; }
    QString error() const { return m_error; }

    // Save the choice if it differs from the last one saved. A call while a save runs saves again
    // once it ends.
    Q_INVOKABLE void save();

    // Run program with arguments, then the helper's arguments, instead of pkexec first-run-privacy.
    // For the unit tests.
    void setCommandForTesting(const QString &program, const QStringList &arguments);

Q_SIGNALS:
    void settingsChanged();
    void savingChanged();
    void errorChanged();
    void saved(bool ok);

private:
    void finish(bool ok);

    bool m_location = true;
    bool m_lastSaved = true;
    bool m_running = true;
    bool m_saveAgain = false;
    QString m_program;
    QStringList m_arguments;
    QProcess *m_process = nullptr;
    QString m_error;
};
