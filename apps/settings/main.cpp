// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "modules.h"
#include "osrelease.h"
#include "pagecatalogue.h"
#include "settingssearch.h"
#include "settingswindow.h"

#include <KAboutData>
#include <KDBusService>
#include <KLocalizedString>
#include <KWindowSystem>

#include <QApplication>
#include <QCommandLineParser>

using namespace OrielOSSettings;

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    KLocalizedString::setApplicationDomain(QByteArrayLiteral(TRANSLATION_DOMAIN));

    KAboutData about(QStringLiteral("orielos-settings"), i18nc("@title", "Settings"), OrielOS::OsRelease::fromSystem().imageVersion(),
        i18nc("@info", "Change how OrielOS works."), KAboutLicense::GPL_V3, i18nc("@info:credit", "© 2026 OrielOS contributors"));
    about.setDesktopFileName(QStringLiteral("org.orielos.Settings"));
    KAboutData::setApplicationData(about);

    QCommandLineParser parser;
    about.setupCommandLine(&parser);
    parser.addPositionalArgument(QStringLiteral("page"),
        i18nc("@info:shell",
            "The page to open: its name, such as display or update, its settings module, such as kcm_kscreen, or a category, alone or as an orielos-settings: "
            "link."),
        QStringLiteral("[page]"));
    parser.process(app);
    about.processCommandLine(&parser);

    // One window: starting Settings again, with Win+I or from the update icon, brings it forward
    // and opens the page asked for.
    KDBusService service(KDBusService::Unique);

    // Settings' own pages, then under More settings every other module System Settings lists, so
    // nothing needs System Settings.
    const PageCatalogue pages = PageCatalogue::standard().available(isInstalled);
    QList<Category> categories = pages.categories();
    QList<Page> all;
    for (const Category &category : std::as_const(categories)) {
        all.append(pages.pages(category.id));
    }
    QList<Page> others = SettingsSearch::otherModules(pages, systemSettingsModules());
    if (!others.isEmpty()) {
        categories.append({ SettingsWindow::moreCategoryId(), i18nc("@title Settings category", "More settings"), QStringLiteral("preferences-other") });
        for (Page &page : others) {
            page.category = SettingsWindow::moreCategoryId();
            all.append(page);
        }
    }
    SettingsWindow window(PageCatalogue(categories, all));
    const QString page = PageCatalogue::targetFromArgument(parser.positionalArguments().value(0));
    if (page.isEmpty() || !window.open(page)) {
        window.openFirst();
    }
    QObject::connect(&service, &KDBusService::activateRequested, &window, [&window](const QStringList &arguments, const QString &) {
        // The first argument is the program.
        if (arguments.size() > 1) {
            window.open(PageCatalogue::targetFromArgument(arguments.at(1)));
        }
        window.show();
        window.raise();
        KWindowSystem::updateStartupId(window.windowHandle());
        KWindowSystem::activateWindow(window.windowHandle());
    });
    window.show();
    return app.exec();
}
