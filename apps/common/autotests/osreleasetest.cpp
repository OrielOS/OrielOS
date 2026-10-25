// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "osrelease.h"

#include <QFile>
#include <QTemporaryDir>
#include <QTest>

using OrielOS::OsRelease;

namespace {

// Fedora 44's /usr/lib/os-release, as shipped in the fedora-release packages.
constexpr QStringView fedoraOsRelease = u"NAME=\"Fedora Linux\"\n"
                                        u"VERSION=\"44 (Forty Four)\"\n"
                                        u"RELEASE_TYPE=stable\n"
                                        u"ID=fedora\n"
                                        u"VERSION_ID=44\n"
                                        u"VERSION_CODENAME=\"\"\n"
                                        u"PRETTY_NAME=\"Fedora Linux 44 (Forty Four)\"\n"
                                        u"ANSI_COLOR=\"0;38;2;60;110;180\"\n"
                                        u"LOGO=fedora-logo-icon\n"
                                        u"CPE_NAME=\"cpe:/o:fedoraproject:fedora:44\"\n"
                                        u"DEFAULT_HOSTNAME=\"fedora\"\n"
                                        u"HOME_URL=\"https://fedoraproject.org/\"\n"
                                        u"DOCUMENTATION_URL=\"https://docs.fedoraproject.org/en-US/fedora/f44/\"\n"
                                        u"SUPPORT_URL=\"https://ask.fedoraproject.org/\"\n"
                                        u"BUG_REPORT_URL=\"https://bugzilla.redhat.com/\"\n"
                                        u"REDHAT_BUGZILLA_PRODUCT=\"Fedora\"\n"
                                        u"REDHAT_BUGZILLA_PRODUCT_VERSION=44\n"
                                        u"REDHAT_SUPPORT_PRODUCT=\"Fedora\"\n"
                                        u"REDHAT_SUPPORT_PRODUCT_VERSION=44\n"
                                        u"SUPPORT_END=2027-05-19\n";

bool writeFile(const QString &path, QByteArrayView content)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(content.data(), content.size()) == content.size();
}

} // namespace

class OsReleaseTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void parsesFedora();
    void parsesValues_data();
    void parsesValues();
    void ignoresCommentsAndBlankLines();
    void ignoresMalformedLines_data();
    void ignoresMalformedLines();
    void laterAssignmentsWin();
    void defaultsWhenUnset();
    void readsFile();
    void missingFileIsInvalid();
    void defaultPathOrder();
    void fallsBackInOrder();
};

void OsReleaseTest::parsesFedora()
{
    const OsRelease os = OsRelease::fromString(fedoraOsRelease);
    QVERIFY(os.isValid());
    QCOMPARE(os.prettyName(), QStringLiteral("Fedora Linux 44 (Forty Four)"));
    QCOMPARE(os.id(), QStringLiteral("fedora"));
    QCOMPARE(os.versionId(), QStringLiteral("44"));
    QCOMPARE(os.value(u"NAME"), QStringLiteral("Fedora Linux"));
    QCOMPARE(os.value(u"VERSION_CODENAME"), QString());
    QCOMPARE(os.value(u"ANSI_COLOR"), QStringLiteral("0;38;2;60;110;180"));
    QCOMPARE(os.value(u"CPE_NAME"), QStringLiteral("cpe:/o:fedoraproject:fedora:44"));
    QCOMPARE(os.value(u"SUPPORT_END"), QStringLiteral("2027-05-19"));
    QCOMPARE(os.value(u"VARIANT_ID"), QString());
    QVERIFY(os.path().isEmpty());
}

void OsReleaseTest::parsesValues_data()
{
    QTest::addColumn<QString>("line");
    QTest::addColumn<QString>("expected");

    QTest::newRow("unquoted") << QStringLiteral("KEY=fedora") << QStringLiteral("fedora");
    QTest::newRow("empty") << QStringLiteral("KEY=") << QString();
    QTest::newRow("double quotes") << QStringLiteral("KEY=\"Fedora Linux\"") << QStringLiteral("Fedora Linux");
    QTest::newRow("single quotes") << QStringLiteral("KEY='Fedora Linux'") << QStringLiteral("Fedora Linux");
    QTest::newRow("empty double quotes") << QStringLiteral("KEY=\"\"") << QString();
    QTest::newRow("empty single quotes") << QStringLiteral("KEY=''") << QString();
    QTest::newRow("escaped double quote") << QStringLiteral("KEY=\"say \\\"hi\\\"\"") << QStringLiteral("say \"hi\"");
    QTest::newRow("escaped backslash") << QStringLiteral("KEY=\"a\\\\b\"") << QStringLiteral("a\\b");
    QTest::newRow("escaped dollar") << QStringLiteral("KEY=\"\\$HOME\"") << QStringLiteral("$HOME");
    QTest::newRow("escaped backtick") << QStringLiteral("KEY=\"\\`date\\`\"") << QStringLiteral("`date`");
    QTest::newRow("other backslash kept") << QStringLiteral("KEY=\"a\\nb\"") << QStringLiteral("a\\nb");
    QTest::newRow("no escapes in single quotes") << QStringLiteral("KEY='a\\\"b'") << QStringLiteral("a\\\"b");
    QTest::newRow("double quote in single quotes") << QStringLiteral("KEY='say \"hi\"'") << QStringLiteral("say \"hi\"");
    QTest::newRow("single quote in double quotes") << QStringLiteral("KEY=\"it's\"") << QStringLiteral("it's");
    QTest::newRow("escaped space unquoted") << QStringLiteral("KEY=a\\ b") << QStringLiteral("a b");
    QTest::newRow("equals in value") << QStringLiteral("KEY=\"a=b\"") << QStringLiteral("a=b");
    QTest::newRow("hash in value") << QStringLiteral("KEY=\"#1\"") << QStringLiteral("#1");
    QTest::newRow("surrounding whitespace") << QStringLiteral("  KEY=\"x\"  ") << QStringLiteral("x");
    QTest::newRow("carriage return") << QStringLiteral("KEY=\"x\"\r") << QStringLiteral("x");
    QTest::newRow("unicode") << QStringLiteral("KEY=\"Ori\u00e9l\"") << QStringLiteral("Ori\u00e9l");
}

void OsReleaseTest::parsesValues()
{
    QFETCH(QString, line);
    QFETCH(QString, expected);
    const OsRelease os = OsRelease::fromString(line);
    QVERIFY(os.isValid());
    QCOMPARE(os.value(u"KEY"), expected);
}

void OsReleaseTest::ignoresCommentsAndBlankLines()
{
    const OsRelease os = OsRelease::fromString(u"# A comment\n"
                                               u"\n"
                                               u"   \n"
                                               u"ID=orielos\n"
                                               u"  # An indented comment\n"
                                               u"#NAME=\"Commented out\"\n"
                                               u"\t\n"
                                               u"VERSION_ID=1\n");
    QVERIFY(os.isValid());
    QCOMPARE(os.id(), QStringLiteral("orielos"));
    QCOMPARE(os.versionId(), QStringLiteral("1"));
    QCOMPARE(os.value(u"NAME"), QString());
}

void OsReleaseTest::ignoresMalformedLines_data()
{
    QTest::addColumn<QString>("line");

    QTest::newRow("no equals sign") << QStringLiteral("KEY");
    QTest::newRow("empty key") << QStringLiteral("=value");
    QTest::newRow("space before equals") << QStringLiteral("KEY =value");
    QTest::newRow("space after equals") << QStringLiteral("KEY= value");
    QTest::newRow("key starts with digit") << QStringLiteral("1KEY=value");
    QTest::newRow("dash in key") << QStringLiteral("MY-KEY=value");
    QTest::newRow("unclosed double quote") << QStringLiteral("KEY=\"value");
    QTest::newRow("unclosed single quote") << QStringLiteral("KEY='value");
    QTest::newRow("escaped closing quote") << QStringLiteral("KEY=\"value\\\"");
    QTest::newRow("two words") << QStringLiteral("KEY=two words");
    QTest::newRow("text after quotes") << QStringLiteral("KEY=\"a\" b");
    QTest::newRow("unescaped dollar") << QStringLiteral("KEY=$HOME");
    QTest::newRow("unescaped backtick") << QStringLiteral("KEY=`date`");
    QTest::newRow("trailing backslash") << QStringLiteral("KEY=value\\");
}

void OsReleaseTest::ignoresMalformedLines()
{
    QFETCH(QString, line);
    const QString text = QStringLiteral("ID=orielos\n") + line + QStringLiteral("\nVERSION_ID=1\n");
    const OsRelease os = OsRelease::fromString(text);
    QCOMPARE(os.id(), QStringLiteral("orielos"));
    QCOMPARE(os.versionId(), QStringLiteral("1"));
    QCOMPARE(os.value(u"KEY"), QString());

    QVERIFY(!OsRelease::fromString(line).isValid());
}

void OsReleaseTest::laterAssignmentsWin()
{
    const OsRelease os = OsRelease::fromString(u"ID=first\nID=second\n");
    QCOMPARE(os.id(), QStringLiteral("second"));
}

void OsReleaseTest::defaultsWhenUnset()
{
    const OsRelease os = OsRelease::fromString(u"NAME=Something\n");
    QVERIFY(os.isValid());
    QCOMPARE(os.prettyName(), QStringLiteral("Linux"));
    QCOMPARE(os.id(), QStringLiteral("linux"));
    QCOMPARE(os.versionId(), QString());

    const OsRelease empty = OsRelease::fromString(u"");
    QVERIFY(!empty.isValid());
    QCOMPARE(empty.prettyName(), QStringLiteral("Linux"));
}

void OsReleaseTest::readsFile()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString path = dir.filePath(QStringLiteral("os-release"));
    QVERIFY(writeFile(path, fedoraOsRelease.toUtf8()));

    const OsRelease os = OsRelease::fromFile(path);
    QVERIFY(os.isValid());
    QCOMPARE(os.path(), path);
    QCOMPARE(os.prettyName(), QStringLiteral("Fedora Linux 44 (Forty Four)"));
}

void OsReleaseTest::missingFileIsInvalid()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const OsRelease os = OsRelease::fromFile(dir.filePath(QStringLiteral("missing")));
    QVERIFY(!os.isValid());
    QVERIFY(os.path().isEmpty());
    QCOMPARE(os.value(u"ID"), QString());
    QCOMPARE(os.prettyName(), QStringLiteral("Linux"));
}

void OsReleaseTest::defaultPathOrder()
{
    QCOMPARE(OsRelease::defaultPaths(), (QStringList { QStringLiteral("/etc/os-release"), QStringLiteral("/usr/lib/os-release") }));
}

void OsReleaseTest::fallsBackInOrder()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString etc = dir.filePath(QStringLiteral("etc-os-release"));
    const QString usr = dir.filePath(QStringLiteral("usr-os-release"));
    const QStringList paths { etc, usr };

    QVERIFY(!OsRelease::fromFirstReadable(paths).isValid());
    QVERIFY(!OsRelease::fromFirstReadable({ }).isValid());

    QVERIFY(writeFile(usr, "ID=fallback\n"));
    OsRelease os = OsRelease::fromFirstReadable(paths);
    QCOMPARE(os.id(), QStringLiteral("fallback"));
    QCOMPARE(os.path(), usr);

    QVERIFY(writeFile(etc, "ID=preferred\n"));
    os = OsRelease::fromFirstReadable(paths);
    QCOMPARE(os.id(), QStringLiteral("preferred"));
    QCOMPARE(os.path(), etc);
}

QTEST_GUILESS_MAIN(OsReleaseTest)

#include "osreleasetest.moc"
