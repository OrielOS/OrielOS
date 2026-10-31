// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "settingssearch.h"

#include "modules.h"

#include <KJsonUtils>
#include <KLocalizedString>

namespace OrielOSSettings {

SettingsSearch::SettingsSearch(PageCatalogue settings, QList<Page> others)
    : m_settings(std::move(settings))
    , m_others({ }, std::move(others))
{
}

SettingsSearch SettingsSearch::installed()
{
    const PageCatalogue available = PageCatalogue::standard().available(isInstalled);
    // A page shows its module's icon unless it has one of its own, as in the Settings window.
    QList<Page> pages;
    for (const Category &category : available.categories()) {
        for (Page page : available.pages(category.id)) {
            if (page.icon.isEmpty() && !isAppModule(page.module)) {
                page.icon = findModule(page.module).iconName();
            }
            pages.append(page);
        }
    }
    PageCatalogue settings(available.categories(), pages);
    QList<Page> others = otherModules(settings, systemSettingsModules());
    return SettingsSearch(std::move(settings), std::move(others));
}

QList<Page> SettingsSearch::otherModules(const PageCatalogue &settings, const QList<KPluginMetaData> &modules)
{
    QList<Page> out;
    for (const KPluginMetaData &metadata : modules) {
        if (settings.page(metadata.pluginId())) {
            continue;
        }
        QStringList keywords;
        // Comma-separated, in the user's language where the module has a translation.
        const QString list = KJsonUtils::readTranslatedString(metadata.rawData(), QStringLiteral("X-KDE-Keywords"));
        for (const QString &keyword : list.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
            keywords.append(keyword.trimmed());
        }
        out.append({ metadata.pluginId(), { }, metadata.name(), metadata.description(), keywords, metadata.pluginId(), metadata.iconName() });
    }
    return out;
}

QList<SettingsResult> SettingsSearch::search(const QString &query) const
{
    QList<SettingsResult> out;
    for (const auto &[page, rank] : m_settings.rankedSearch(query)) {
        const std::optional<Category> category = m_settings.category(page.category);
        out.append({
            page.id,
            page.title,
            i18nc("@info Where a found setting opens: %1 is a category of Settings", "Settings › %1", category ? category->title : QString()),
            page.icon,
            { QStringLiteral("orielos-settings"), page.id },
            rank,
            true,
        });
    }
    for (const auto &[page, rank] : m_others.rankedSearch(query)) {
        out.append({
            page.module,
            page.title,
            i18nc("@info Where a found setting opens", "Settings › More settings"),
            page.icon,
            { QStringLiteral("orielos-settings"), page.module },
            rank,
            false,
        });
    }
    return out;
}

} // namespace OrielOSSettings
