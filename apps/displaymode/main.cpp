// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Windows + P: a panel above the right of the taskbar to choose how the screens are used: this
// computer's screen only, the same picture on every screen, one desktop across them, or the other
// screens only. Pressing Windows + P again while it shows moves to the next choice, since a second
// start hands over to the first through D-Bus; Enter or a click applies, Escape closes.
// "orielos-display-mode --apply MODE" applies a mode (main, duplicate, extend or second) with no
// panel, for scripts.

#include "displaylayout.h"
#include "displayswitcher.h"
#include "osrelease.h"

#include <KAboutData>
#include <KDBusService>
#include <KLocalizedQmlContext>
#include <KLocalizedString>
#include <LayerShellQt/Window>

#include <QCommandLineParser>
#include <QGuiApplication>
#include <QHash>
#include <QQmlApplicationEngine>
#include <QQuickWindow>

#include <cstdio>

namespace {

// --apply MODE: applies the mode once the screen configuration has been read, then ends.
int applyMode(const QString &name)
{
    static const QHash<QString, DisplayLayout::Mode> modes = {
        { QStringLiteral("main"), DisplayLayout::Mode::MainOnly },
        { QStringLiteral("duplicate"), DisplayLayout::Mode::Duplicate },
        { QStringLiteral("extend"), DisplayLayout::Mode::Extend },
        { QStringLiteral("second"), DisplayLayout::Mode::OthersOnly },
    };
    if (!modes.contains(name)) {
        std::fprintf(stderr, "orielos-display-mode: --apply takes main, duplicate, extend or second, not %s\n", qUtf8Printable(name));
        return 2;
    }
    DisplaySwitcher switcher;
    QObject::connect(&switcher, &DisplaySwitcher::applied, qApp, [](bool succeeded) { QCoreApplication::exit(succeeded ? 0 : 1); });
    QObject::connect(&switcher, &DisplaySwitcher::unavailable, qApp, []() { QCoreApplication::exit(1); });
    const auto apply = [&switcher, mode = modes.value(name)]() { switcher.apply(int(mode)); };
    if (switcher.ready()) {
        apply();
    } else {
        QObject::connect(&switcher, &DisplaySwitcher::changed, qApp, apply, Qt::SingleShotConnection);
    }
    return QCoreApplication::exec();
}

} // namespace

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    KLocalizedString::setApplicationDomain(QByteArrayLiteral(TRANSLATION_DOMAIN));

    KAboutData about(QStringLiteral("orielos-display-mode"), i18nc("@title", "Display mode"), OrielOS::OsRelease::fromSystem().imageVersion(),
        i18nc("@info", "Choose how the screens are used"), KAboutLicense::GPL_V3);
    about.setDesktopFileName(QStringLiteral("org.orielos.DisplayMode"));
    KAboutData::setApplicationData(about);

    QCommandLineParser parser;
    const QCommandLineOption applyOption(
        QStringLiteral("apply"), i18nc("@info:shell", "Apply a mode without the panel: main, duplicate, extend or second."), QStringLiteral("mode"));
    parser.addOption(applyOption);
    about.setupCommandLine(&parser);
    parser.process(app);
    about.processCommandLine(&parser);
    if (parser.isSet(applyOption)) {
        return applyMode(parser.value(applyOption));
    }

    // A second start (Windows + P pressed again) asks this one to move to the next choice and ends.
    KDBusService service(KDBusService::Unique);

    QQmlApplicationEngine engine;
    KLocalization::setupLocalizedContext(&engine);
    engine.loadFromModule("org.orielos.displaymode", "Main");
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    if (!window) {
        return 1;
    }

    // A layer-shell surface above the right of the taskbar, kept clear of it by the taskbar's
    // reserved space, with Sill's 12 px gap.
    auto *layer = LayerShellQt::Window::get(window);
    layer->setLayer(LayerShellQt::Window::LayerTop);
    layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorBottom | LayerShellQt::Window::AnchorRight));
    layer->setMargins(QMargins(0, 0, 12, 12));
    layer->setExclusiveZone(0);
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
    layer->setScope(QStringLiteral("orielos-display-mode"));

    QObject::connect(&service, &KDBusService::activateRequested, window, [window]() { QMetaObject::invokeMethod(window, "next"); });

    window->show();
    window->requestActivate();
    return app.exec();
}
