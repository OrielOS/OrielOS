// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// OrielOS's administrator prompt: the session's polkit authentication agent, in place of Plasma's.
// It runs for the whole session (orielos-polkit-agent.service) and shows the prompt over the
// dimmed screen whenever polkit asks for an administrator.

#include "agent.h"
#include "osrelease.h"

#include <KAboutData>
#include <KLocalizedQmlContext>
#include <KLocalizedString>
#include <LayerShellQt/Window>
#include <PolkitQt1/Subject>

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>

#include <cstdio>
#include <unistd.h>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    KLocalizedString::setApplicationDomain(QByteArrayLiteral(TRANSLATION_DOMAIN));

    KAboutData about(QStringLiteral("orielos-polkit-agent"), i18nc("@title", "Administrator permission"), OrielOS::OsRelease::fromSystem().imageVersion(),
        i18nc("@info", "Asks for an administrator's permission when an app needs it"), KAboutLicense::GPL_V3);
    about.setDesktopFileName(QStringLiteral("org.orielos.PolkitAgent"));
    KAboutData::setApplicationData(about);

    Agent agent;
    const PolkitQt1::UnixSessionSubject session(getpid());
    if (!agent.registerListener(session, QStringLiteral("/org/orielos/PolicyKit1/AuthenticationAgent"))) {
        std::fprintf(stderr, "orielos-polkit-agent: polkit didn't take this agent for the session (is another agent running?)\n");
        return 1;
    }

    QQmlApplicationEngine engine;
    KLocalization::setupLocalizedContext(&engine);
    engine.setInitialProperties({ { QStringLiteral("agent"), QVariant::fromValue(&agent) } });
    engine.loadFromModule("org.orielos.polkitagent", "Main");
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    if (!window) {
        return 1;
    }

    // The whole screen, above everything, with the keyboard to itself while it shows.
    auto *layer = LayerShellQt::Window::get(window);
    layer->setLayer(LayerShellQt::Window::LayerOverlay);
    layer->setAnchors(LayerShellQt::Window::Anchors(
        LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight));
    layer->setExclusiveZone(-1);
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
    layer->setScope(QStringLiteral("orielos-admin-prompt"));

    return app.exec();
}
