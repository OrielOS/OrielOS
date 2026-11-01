// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "recentactivity.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace OrielOSSettingsPages;

namespace {

const QDateTime Now(QDate(2026, 10, 30), QTime(15, 0)); // a Friday

std::pair<QString, QString> fakeLookup(const QString &id)
{
    if (id.startsWith(QLatin1String("exe:"))) {
        return { id.mid(4), QStringLiteral("application-x-executable") };
    }
    return { id.section(QLatin1Char('.'), -1), id };
}

void writeState(const QString &path, const QByteArray &json)
{
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    file.write(json);
}

qint64 ago(qint64 seconds)
{
    return Now.toSecsSinceEpoch() - seconds;
}

} // namespace

class RecentActivityTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void listsEachKindNewestFirst()
    {
        QTemporaryDir dir;
        const QString state = dir.filePath(QStringLiteral("privacy-activity.json"));
        writeState(state,
            QStringLiteral("{\"camera\": {\"org.kde.kamoso\": %1, \"com.discordapp.Discord\": %2}, \"microphone\": {\"exe:arecord\": %3}}")
                .arg(ago(3600))
                .arg(ago(10))
                .arg(ago(2 * 24 * 3600))
                .toUtf8());
        RecentActivity activity(state, [] { return Now; }, &fakeLookup);

        QCOMPARE(activity.camera().size(), 2);
        const QVariantMap first = activity.camera().at(0).toMap();
        QCOMPARE(first.value(QStringLiteral("name")).toString(), QStringLiteral("Discord"));
        QCOMPARE(first.value(QStringLiteral("icon")).toString(), QStringLiteral("com.discordapp.Discord"));
        QVERIFY(first.value(QStringLiteral("inUse")).toBool());
        QCOMPARE(first.value(QStringLiteral("when")).toString(), QStringLiteral("Using it now"));
        const QVariantMap second = activity.camera().at(1).toMap();
        QCOMPARE(second.value(QStringLiteral("name")).toString(), QStringLiteral("kamoso"));
        QVERIFY(!second.value(QStringLiteral("inUse")).toBool());

        QCOMPARE(activity.microphone().size(), 1);
        QCOMPARE(activity.microphone().at(0).toMap().value(QStringLiteral("name")).toString(), QStringLiteral("arecord"));
        QVERIFY(activity.location().isEmpty());
    }

    void leavesOutWhatsOlderThanAWeek()
    {
        QTemporaryDir dir;
        const QString state = dir.filePath(QStringLiteral("privacy-activity.json"));
        writeState(state,
            QStringLiteral("{\"location\": {\"org.gnome.Maps\": %1, \"org.kde.marble\": %2, \"broken\": \"soon\"}}")
                .arg(ago(8 * 24 * 3600))
                .arg(ago(6 * 24 * 3600))
                .toUtf8());
        RecentActivity activity(state, [] { return Now; }, &fakeLookup);
        QCOMPARE(activity.location().size(), 1);
        QCOMPARE(activity.location().at(0).toMap().value(QStringLiteral("id")).toString(), QStringLiteral("org.kde.marble"));
    }

    void saysWhen()
    {
        QCOMPARE(RecentActivity::whenText(Now.addSecs(-5), Now), QStringLiteral("Using it now"));
        QVERIFY(RecentActivity::whenText(Now.addSecs(-3600), Now).startsWith(QStringLiteral("Last used today at ")));
        QVERIFY(RecentActivity::whenText(Now.addDays(-1), Now).startsWith(QStringLiteral("Last used yesterday at ")));
        QVERIFY(RecentActivity::whenText(Now.addDays(-3), Now).startsWith(QStringLiteral("Last used on Tuesday at ")));
    }

    void copesWithoutAList()
    {
        QTemporaryDir dir;
        RecentActivity activity(dir.filePath(QStringLiteral("none/privacy-activity.json")), [] { return Now; }, &fakeLookup);
        QVERIFY(activity.camera().isEmpty());
        QVERIFY(activity.microphone().isEmpty());
        QVERIFY(activity.location().isEmpty());
    }

    void followsTheList()
    {
        QTemporaryDir dir;
        const QString state = dir.filePath(QStringLiteral("privacy-activity.json"));
        writeState(state, "{}");
        RecentActivity activity(state, [] { return Now; }, &fakeLookup);
        QSignalSpy changed(&activity, &RecentActivity::changed);
        writeState(state, QStringLiteral("{\"microphone\": {\"org.kde.kdenlive\": %1}}").arg(ago(60)).toUtf8());
        QVERIFY(changed.wait(2000));
        QCOMPARE(activity.microphone().size(), 1);
    }
};

QTEST_GUILESS_MAIN(RecentActivityTest)

#include "recentactivitytest.moc"
