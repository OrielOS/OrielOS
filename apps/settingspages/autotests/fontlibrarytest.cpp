// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fontlibrary.h"

#include <QDirIterator>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using OrielOSSettingsPages::FontLibrary;

class FontLibraryTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;

    // A font file of the system's to install a copy of.
    static QString systemFont()
    {
        QDirIterator fonts(QStringLiteral("/usr/share/fonts"), { QStringLiteral("*.ttf"), QStringLiteral("*.otf") }, QDir::Files, QDirIterator::Subdirectories);
        return fonts.hasNext() ? fonts.next() : QString();
    }

private Q_SLOTS:
    void recognisesFontFiles()
    {
        QVERIFY(FontLibrary::isFontFile(QUrl::fromLocalFile(QStringLiteral("/tmp/Font.TTF"))));
        QVERIFY(FontLibrary::isFontFile(QUrl::fromLocalFile(QStringLiteral("/tmp/font.otc"))));
        QVERIFY(!FontLibrary::isFontFile(QUrl::fromLocalFile(QStringLiteral("/tmp/font.zip"))));
        QVERIFY(!FontLibrary::isFontFile(QUrl(QStringLiteral("https://example.org/font.ttf"))));
    }

    void listsFamilies()
    {
        FontLibrary library;
        const QVariantList families = library.families();
        QVERIFY(!families.isEmpty());
        const QVariantMap first = families.constFirst().toMap();
        QVERIFY(!first.value(QStringLiteral("name")).toString().isEmpty());
        QVERIFY(first.value(QStringLiteral("faces")).toInt() >= 0);
    }

    void installsFonts()
    {
        const QString font = systemFont();
        if (font.isEmpty()) {
            QSKIP("no font file in /usr/share/fonts to install a copy of");
        }
        const QString folder = m_dir.filePath(QStringLiteral("fonts"));
        const QString broken = m_dir.filePath(QStringLiteral("broken.ttf"));
        QFile file(broken);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("not a font");
        file.close();

        FontLibrary library;
        library.setForTesting(folder);
        QSignalSpy changed(&library, &FontLibrary::changed);
        const QString name = QFileInfo(font).fileName();
        QVariantMap done = library.install({ QUrl::fromLocalFile(font), QUrl::fromLocalFile(broken), QUrl::fromLocalFile(m_dir.filePath(QStringLiteral("notes.txt"))) });
        QCOMPARE(done.value(QStringLiteral("installed")).toStringList(), QStringList { name });
        QCOMPARE(done.value(QStringLiteral("unsupported")).toStringList(), (QStringList { QStringLiteral("broken.ttf"), QStringLiteral("notes.txt") }));
        QVERIFY(QFile::exists(folder + QLatin1Char('/') + name));
        // A file that isn't really a font isn't left behind.
        QVERIFY(!QFile::exists(folder + QStringLiteral("/broken.ttf")));
        QCOMPARE(changed.count(), 1);

        // The same file again isn't replaced.
        done = library.install({ QUrl::fromLocalFile(font) });
        QCOMPARE(done.value(QStringLiteral("existing")).toStringList(), QStringList { name });
        QVERIFY(done.value(QStringLiteral("installed")).toStringList().isEmpty());
        QCOMPARE(changed.count(), 1);
    }
};

QTEST_MAIN(FontLibraryTest)

#include "fontlibrarytest.moc"
