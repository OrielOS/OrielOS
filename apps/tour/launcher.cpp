// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "launcher.h"

#include <KIO/ApplicationLauncherJob>
#include <KNotificationJobUiDelegate>
#include <KService>

namespace OrielOSTour {

void Launcher::openApp(const QString &desktopName)
{
    const KService::Ptr service = KService::serviceByDesktopName(desktopName);
    if (!service) {
        return;
    }
    auto *job = new KIO::ApplicationLauncherJob(service);
    job->setUiDelegate(new KNotificationJobUiDelegate(KJobUiDelegate::AutoErrorHandlingEnabled));
    job->start();
}

} // namespace OrielOSTour
