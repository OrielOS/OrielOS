// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "pagecatalogue.h"

#include <KLocalizedString>

#include <algorithm>

namespace OrielOSSettings {

namespace {

// Lower case, without accents, so "Écran" and "ecran" match.
QString normalise(const QString &text)
{
    const QString decomposed = text.toCaseFolded().normalized(QString::NormalizationForm_KD);
    QString out;
    out.reserve(decomposed.size());
    for (const QChar c : decomposed) {
        if (c.category() != QChar::Mark_NonSpacing) {
            out.append(c);
        }
    }
    return out;
}

QStringList words(const QString &text)
{
    QStringList out;
    QString current;
    for (const QChar c : normalise(text)) {
        if (c.isLetterOrNumber()) {
            current.append(c);
        } else if (!current.isEmpty()) {
            out.append(current);
            current.clear();
        }
    }
    if (!current.isEmpty()) {
        out.append(current);
    }
    return out;
}

// Whether every query word starts some word of the text.
bool prefixesAll(const QStringList &query, const QStringList &text)
{
    return std::all_of(query.cbegin(), query.cend(), [&text](const QString &word) {
        return std::any_of(text.cbegin(), text.cend(), [&word](const QString &candidate) { return candidate.startsWith(word); });
    });
}

QStringList keywords(const QString &list)
{
    return list.split(QLatin1Char(';'), Qt::SkipEmptyParts);
}

} // namespace

PageCatalogue::PageCatalogue(QList<Category> categories, QList<Page> pages)
    : m_categories(std::move(categories))
    , m_pages(std::move(pages))
{
}

PageCatalogue PageCatalogue::standard()
{
    const QString system = QStringLiteral("system");
    const QString devices = QStringLiteral("devices");
    const QString network = QStringLiteral("network");
    const QString personalisation = QStringLiteral("personalisation");
    const QString apps = QStringLiteral("apps");
    const QString accounts = QStringLiteral("accounts");
    const QString time = QStringLiteral("time");
    const QString update = QStringLiteral("update");

    QList<Category> categories {
        { system, i18nc("@title Settings category", "System"), QStringLiteral("computer") },
        { devices, i18nc("@title Settings category", "Bluetooth & devices"), QStringLiteral("preferences-system-bluetooth") },
        { network, i18nc("@title Settings category", "Network & internet"), QStringLiteral("preferences-system-network") },
        { personalisation, i18nc("@title Settings category", "Personalisation"), QStringLiteral("preferences-desktop-theme") },
        { apps, i18nc("@title Settings category", "Apps"), QStringLiteral("preferences-desktop-default-applications") },
        { accounts, i18nc("@title Settings category", "Accounts"), QStringLiteral("preferences-system-users") },
        { time, i18nc("@title Settings category", "Time & language"), QStringLiteral("preferences-system-time") },
        { update, i18nc("@title Settings category", "Update"), QStringLiteral("system-software-update") },
    };

    // Search words are a translatable list separated by ";", as in desktop entries.
    QList<Page> pages {
        { QStringLiteral("display"), system, i18nc("@title Settings page", "Display"), i18nc("@info", "Resolution, scale, refresh rate, HDR and arrangement"),
            keywords(i18nc("@info:keywords Search words for the Display page, separated by ;",
                "display;screen;monitor;resolution;scale;scaling;size;refresh rate;hz;hdr;orientation;rotation;multiple displays")),
            QStringLiteral("kcm_kscreen"), { } },
        { QStringLiteral("night-light"), system, i18nc("@title Settings page", "Night light"), i18nc("@info", "Warmer colours in the evening"),
            keywords(i18nc("@info:keywords Search words for the Night light page, separated by ;", "night light;blue light;warm;colour temperature")),
            QStringLiteral("kcm_nightlight"), { } },
        { QStringLiteral("sound"), system, i18nc("@title Settings page", "Sound"), i18nc("@info", "Speakers, headphones, microphones and volume"),
            keywords(i18nc("@info:keywords Search words for the Sound page, separated by ;",
                "sound;audio;volume;speakers;headphones;headset;microphone;mic;output;input")),
            QStringLiteral("kcm_pulseaudio"), { } },
        { QStringLiteral("notifications"), system, i18nc("@title Settings page", "Notifications"), i18nc("@info", "Alerts from apps and the system"),
            keywords(i18nc("@info:keywords Search words for the Notifications page, separated by ;", "notifications;alerts;do not disturb;focus")),
            QStringLiteral("kcm_notifications"), { } },
        { QStringLiteral("power"), system, i18nc("@title Settings page", "Power & sleep"), i18nc("@info", "Sleep, screen off and battery"),
            keywords(i18nc(
                "@info:keywords Search words for the Power & sleep page, separated by ;", "power;sleep;battery;screen off;turn off;lid;energy;power plan")),
            QStringLiteral("kcm_powerdevilprofilesconfig"), { } },
        { QStringLiteral("about"), system, i18nc("@title Settings page", "About"), i18nc("@info", "This computer, its specifications and OrielOS's version"),
            keywords(i18nc("@info:keywords Search words for the About page, separated by ;",
                "about;system information;specifications;specs;version;processor;memory;ram;graphics card;pc info")),
            QStringLiteral("kcm_about-distro"), { } },
        { QStringLiteral("bluetooth"), devices, i18nc("@title Settings page", "Bluetooth"), i18nc("@info", "Pair headphones, controllers, mice and keyboards"),
            keywords(i18nc("@info:keywords Search words for the Bluetooth page, separated by ;", "bluetooth;pair;wireless;headphones;controller")),
            QStringLiteral("kcm_bluetooth"), { } },
        { QStringLiteral("mouse"), devices, i18nc("@title Settings page", "Mouse"), i18nc("@info", "Pointer speed, buttons and scrolling"),
            keywords(i18nc("@info:keywords Search words for the Mouse page, separated by ;", "mouse;pointer;cursor speed;acceleration;scroll;buttons")),
            QStringLiteral("kcm_mouse"), { } },
        { QStringLiteral("touchpad"), devices, i18nc("@title Settings page", "Touchpad"), i18nc("@info", "Tapping, scrolling and gestures"),
            keywords(i18nc("@info:keywords Search words for the Touchpad page, separated by ;", "touchpad;trackpad;tap to click;gestures;scroll")),
            QStringLiteral("kcm_touchpad"), { } },
        { QStringLiteral("keyboard"), devices, i18nc("@title Settings page", "Keyboard"), i18nc("@info", "Layouts, key repeat and NumLock"),
            keywords(i18nc(
                "@info:keywords Search words for the Keyboard page, separated by ;", "keyboard;keyboard layout;input language;typing;key repeat;numlock")),
            QStringLiteral("kcm_keyboard"), { } },
        { QStringLiteral("printers"), devices, i18nc("@title Settings page", "Printers"), i18nc("@info", "Add and manage printers"),
            keywords(i18nc("@info:keywords Search words for the Printers page, separated by ;", "printers;printing;print;scanner")),
            QStringLiteral("kcm_printer_manager"), { } },
        { QStringLiteral("game-controllers"), devices, i18nc("@title Settings page", "Game controllers"), i18nc("@info", "Test controllers and joysticks"),
            keywords(i18nc("@info:keywords Search words for the Game controllers page, separated by ;", "game controllers;gamepad;joystick;xbox;playstation")),
            QStringLiteral("kcm_gamecontroller"), { } },
        { QStringLiteral("accessories"), devices, i18nc("@title Settings page", "Accessory apps"),
            i18nc("@info", "Solaar, Piper and OpenRGB for gaming mice, keyboards and lighting"),
            keywords(i18nc("@info:keywords Search words for the Accessory apps page, separated by ;",
                "accessories;peripherals;gaming mouse;dpi;rgb;lighting;logitech;razer;solaar;piper;openrgb")),
            QStringLiteral("kcm_orielos_accessories"), { } },
        { QStringLiteral("network"), network, i18nc("@title Settings page", "Network & internet"), i18nc("@info", "Wi-Fi, Ethernet, VPN and hotspot"),
            keywords(i18nc("@info:keywords Search words for the Network page, separated by ;",
                "network;internet;wifi;wi-fi;wireless;ethernet;vpn;hotspot;mobile broadband;ip address;dns")),
            QStringLiteral("kcm_networkmanagement"), { } },
        { QStringLiteral("proxy"), network, i18nc("@title Settings page", "Proxy"), i18nc("@info", "Send internet traffic through a proxy server"),
            keywords(i18nc("@info:keywords Search words for the Proxy page, separated by ;", "proxy;proxy server")), QStringLiteral("kcm_proxy"), { } },
        { QStringLiteral("background"), personalisation, i18nc("@title Settings page", "Background"), i18nc("@info", "The picture on your desktop"),
            keywords(i18nc("@info:keywords Search words for the Background page, separated by ;", "background;wallpaper;desktop background;picture")),
            QStringLiteral("kcm_wallpaper"), { } },
        { QStringLiteral("themes"), personalisation, i18nc("@title Settings page", "Themes"),
            i18nc("@info", "Light and dark mode, and the look of the desktop"),
            keywords(i18nc("@info:keywords Search words for the Themes page, separated by ;", "themes;dark mode;light mode;colours;colors;appearance;look")),
            QStringLiteral("kcm_lookandfeel"), { } },
        { QStringLiteral("accent"), personalisation, i18nc("@title Settings page", "Accent colour"),
            i18nc("@info", "The colour of highlights, selected items and focus rings"),
            keywords(i18nc("@info:keywords Search words for the Accent colour page, separated by ;", "accent colour;accent color;colours;colors;highlight")),
            QStringLiteral("kcm_orielos_accent"), { } },
        { QStringLiteral("lock-screen"), personalisation, i18nc("@title Settings page", "Lock screen"),
            i18nc("@info", "When the screen locks, and its picture"),
            keywords(i18nc("@info:keywords Search words for the Lock screen page, separated by ;", "lock screen;screen lock;lock;sign-in;wake")),
            QStringLiteral("kcm_screenlocker"), { } },
        { QStringLiteral("default-apps"), apps, i18nc("@title Settings page", "Default apps"),
            i18nc("@info", "Which app opens web pages, email, music and more"),
            keywords(i18nc("@info:keywords Search words for the Default apps page, separated by ;", "default apps;default browser;open with;file types")),
            QStringLiteral("kcm_componentchooser"), { } },
        { QStringLiteral("startup-apps"), apps, i18nc("@title Settings page", "Startup"), i18nc("@info", "Apps that start when you sign in"),
            keywords(i18nc("@info:keywords Search words for the Startup page, separated by ;", "startup;autostart;start at login;login items")),
            QStringLiteral("kcm_autostart"), { } },
        { QStringLiteral("your-info"), accounts, i18nc("@title Settings page", "Your info"),
            i18nc("@info", "Your name, picture and password, and other accounts"),
            keywords(i18nc(
                "@info:keywords Search words for the Your info page, separated by ;", "accounts;users;your info;password;account picture;add user;family")),
            QStringLiteral("kcm_users"), { } },
        { QStringLiteral("date-time"), time, i18nc("@title Settings page", "Date & time"), i18nc("@info", "Time zone and setting the clock"),
            keywords(i18nc("@info:keywords Search words for the Date & time page, separated by ;", "date;time;clock;time zone;timezone;ntp")),
            QStringLiteral("kcm_clock"), { } },
        { QStringLiteral("language-region"), time, i18nc("@title Settings page", "Language & region"), i18nc("@info", "Language, formats and units"),
            keywords(i18nc("@info:keywords Search words for the Language & region page, separated by ;",
                "language;region;locale;formats;date format;currency;units;keyboard layout")),
            QStringLiteral("kcm_regionandlang"), { } },
        { QStringLiteral("update"), update, i18nc("@title Settings page", "OrielOS Update"), i18nc("@info", "Updates, the update channel and going back"),
            keywords(i18nc("@info:keywords Search words for the Update page, separated by ;",
                "update;updates;windows update;check for updates;upgrade;version;pause updates;roll back;go back")),
            QStringLiteral("kcm_orielos_update"), { } },
    };
    return PageCatalogue(std::move(categories), std::move(pages));
}

PageCatalogue PageCatalogue::available(const std::function<bool(const QString &module)> &isInstalled) const
{
    QList<Page> pages;
    std::copy_if(m_pages.cbegin(), m_pages.cend(), std::back_inserter(pages), [&isInstalled](const Page &page) { return isInstalled(page.module); });
    QList<Category> categories;
    std::copy_if(m_categories.cbegin(), m_categories.cend(), std::back_inserter(categories), [&pages](const Category &category) {
        return std::any_of(pages.cbegin(), pages.cend(), [&category](const Page &page) { return page.category == category.id; });
    });
    return PageCatalogue(std::move(categories), std::move(pages));
}

std::optional<Category> PageCatalogue::category(const QString &id) const
{
    const auto found = std::find_if(m_categories.cbegin(), m_categories.cend(), [&id](const Category &category) { return category.id == id; });
    if (found == m_categories.cend()) {
        return std::nullopt;
    }
    return *found;
}

QList<Page> PageCatalogue::pages(const QString &categoryId) const
{
    QList<Page> out;
    std::copy_if(m_pages.cbegin(), m_pages.cend(), std::back_inserter(out), [&categoryId](const Page &page) { return page.category == categoryId; });
    return out;
}

std::optional<Page> PageCatalogue::page(const QString &idOrModule) const
{
    const auto found
        = std::find_if(m_pages.cbegin(), m_pages.cend(), [&idOrModule](const Page &page) { return page.id == idOrModule || page.module == idOrModule; });
    if (found == m_pages.cend()) {
        return std::nullopt;
    }
    return *found;
}

QList<Page> PageCatalogue::search(const QString &query) const
{
    QList<Page> out;
    for (const auto &match : rankedSearch(query)) {
        out.append(match.first);
    }
    return out;
}

QList<std::pair<Page, int>> PageCatalogue::rankedSearch(const QString &query) const
{
    // The query is split once; Start's search runs this on every key.
    const QStringList queryWords = words(query);
    QList<std::pair<Page, int>> matches;
    if (queryWords.isEmpty()) {
        return matches;
    }
    for (const Page &page : m_pages) {
        const int rank = this->rank(page, queryWords);
        if (rank >= 0) {
            matches.append({ page, rank });
        }
    }
    // Equal matches keep the catalogue's order.
    std::stable_sort(matches.begin(), matches.end(), [](const auto &a, const auto &b) { return a.second < b.second; });
    return matches;
}

int PageCatalogue::rank(const Page &page, const QString &query) const
{
    return rank(page, words(query));
}

int PageCatalogue::rank(const Page &page, const QStringList &queryWords) const
{
    if (queryWords.isEmpty()) {
        return -1;
    }
    // Each list is only built when the cheaper ones before it don't match.
    const QStringList title = words(page.title);
    if (title.join(QLatin1Char(' ')).startsWith(queryWords.join(QLatin1Char(' ')))) {
        return 0;
    }
    if (prefixesAll(queryWords, title)) {
        return 1;
    }
    QStringList named = title;
    for (const QString &keyword : page.keywords) {
        named += words(keyword);
    }
    if (prefixesAll(queryWords, named)) {
        return 2;
    }
    QStringList everything = named;
    if (const std::optional<Category> category = this->category(page.category)) {
        everything += words(category->title);
    }
    everything += words(page.description);
    if (prefixesAll(queryWords, everything)) {
        return 3;
    }
    return -1;
}

} // namespace OrielOSSettings
