// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "runbox.h"
#include "runtarget.h"

#include <KConfigGroup>
#include <KIO/CommandLauncherJob>
#include <KIO/OpenUrlJob>
#include <KLocalizedString>
#include <KSharedConfig>

#include <QDir>
#include <QStandardPaths>
#include <QUrl>

namespace {

KConfigGroup historyGroup()
{
    return KConfigGroup(KSharedConfig::openConfig(QStringLiteral("orielos-runrc")), QStringLiteral("History"));
}

} // namespace

RunBoxModel::RunBoxModel(QObject *parent)
    : QObject(parent)
    , m_history(historyGroup().readEntry("Entries", QStringList()))
{
}

void RunBoxModel::run(const QString &text)
{
    if (m_busy) {
        return;
    }
    const RunBox::Target target = RunBox::resolve(text, QDir::homePath(), [](const QString &program) { return QStandardPaths::findExecutable(program); });

    KJob *job = nullptr;
    switch (target.kind) {
    case RunBox::Target::Kind::Empty:
        return;
    case RunBox::Target::Kind::NotFound:
        finish(text, false);
        return;
    case RunBox::Target::Kind::Url:
    case RunBox::Target::Kind::Path:
        job = new KIO::OpenUrlJob(QUrl(target.value));
        break;
    case RunBox::Target::Kind::Command:
        job = new KIO::CommandLauncherJob(target.value);
        break;
    }

    m_busy = true;
    Q_EMIT busyChanged();
    connect(job, &KJob::result, this, [this, text](KJob *finished) { finish(text, finished->error() == 0); });
    job->start();
}

void RunBoxModel::finish(const QString &text, bool ok)
{
    if (m_busy) {
        m_busy = false;
        Q_EMIT busyChanged();
    }
    if (!ok) {
        Q_EMIT failed(
            i18nc("@info %1 is what was typed", "OrielOS can't find \"%1\". Make sure you typed the name correctly, and then try again.", text.trimmed()));
        return;
    }
    m_history = RunBox::remember(m_history, text);
    KConfigGroup group = historyGroup();
    group.writeEntry("Entries", m_history);
    group.sync();
    Q_EMIT historyChanged();
    Q_EMIT started();
}
