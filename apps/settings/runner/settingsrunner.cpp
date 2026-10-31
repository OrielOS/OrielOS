// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "settingssearch.h"

#include <KIO/CommandLauncherJob>
#include <KNotificationJobUiDelegate>
#include <KRunner/AbstractRunner>
#include <KRunner/QueryMatch>
#include <KRunner/RunnerContext>

#include <optional>

namespace {

using namespace OrielOSSettings;

// Finds settings for Start's search and KRunner: Settings' pages and the other modules System
// Settings lists, all opened in Settings. It takes the place of System Settings' own runner, which
// opens every module in System Settings.
class SettingsRunner : public KRunner::AbstractRunner
{
    Q_OBJECT

public:
    SettingsRunner(QObject *parent, const KPluginMetaData &metaData)
        : KRunner::AbstractRunner(parent, metaData)
    {
    }

    // Runs on the runner's own thread, before any match: finding every settings module reads each
    // one's metadata, which shouldn't hold up the thread that loads the runner. Modules only change
    // with the OS, which needs a restart, so they're found once.
    void init() override { m_search.emplace(SettingsSearch::installed()); }

    // Runs on the runner's own thread too; m_search isn't changed after init().
    void match(KRunner::RunnerContext &context) override
    {
        if (!m_search) {
            return;
        }
        QList<KRunner::QueryMatch> matches;
        const QList<SettingsResult> results = m_search->search(context.query());
        for (qsizetype i = 0; i < results.size(); ++i) {
            const SettingsResult &result = results.at(i);
            KRunner::QueryMatch match(this);
            match.setId(result.id);
            match.setText(result.title);
            match.setSubtext(result.subtext);
            match.setIconName(result.icon);
            match.setData(result.command);
            // A page whose name matches beats an app found by its keywords; the modules under More
            // settings come after Settings' own pages.
            using Relevance = KRunner::QueryMatch::CategoryRelevance;
            if (result.inSettings) {
                match.setCategoryRelevance(result.rank <= 1 ? Relevance::High : Relevance::Moderate);
            } else {
                match.setCategoryRelevance(result.rank <= 1 ? Relevance::Moderate : Relevance::Low);
            }
            match.setRelevance(qMax(0.1, 1.0 - 0.2 * result.rank - 0.01 * qreal(i)));
            matches.append(match);
        }
        context.addMatches(matches);
    }

    void run(const KRunner::RunnerContext &context, const KRunner::QueryMatch &match) override
    {
        Q_UNUSED(context)
        const QStringList command = match.data().toStringList();
        if (command.isEmpty()) {
            return;
        }
        auto *job = new KIO::CommandLauncherJob(command.first(), command.mid(1));
        // Names the app for the activation token, so its window comes to the front.
        job->setDesktopName(QStringLiteral("org.orielos.Settings"));
        // A program that can't start says so in a notification.
        job->setUiDelegate(new KNotificationJobUiDelegate(KJobUiDelegate::AutoErrorHandlingEnabled));
        job->start();
    }

private:
    std::optional<SettingsSearch> m_search;
};

} // namespace

K_PLUGIN_CLASS_WITH_JSON(SettingsRunner, "krunner_orielos_settings.json")

#include "settingsrunner.moc"
