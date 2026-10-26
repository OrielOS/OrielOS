// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The apps for gaming mice, keyboards and RGB lighting, which come from the Store. OrielOS has the
// system pieces they need (their udev rules and ratbagd); each app opens if it's installed, or its
// Store page if it isn't.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property StoreApps store: StoreApps {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }

    // An app installed from the Store while the page is open soon shows as installed.
    Timer {
        interval: 3000
        repeat: true
        running: root.visible
        onTriggered: root.store.refresh()
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.l10n.i18nc("@info", "These apps set up gaming mice, keyboards and RGB lighting. They come from the Store; OrielOS already has the system parts they need.")
        }

        Repeater {
            model: root.store.apps

            delegate: Kirigami.AbstractCard {
                id: card

                required property var modelData

                Layout.fillWidth: true

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.large
                        Layout.preferredHeight: Kirigami.Units.iconSizes.large
                        source: card.modelData.icon
                        fallback: "plasmadiscover"
                        Accessible.ignored: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Heading {
                            Layout.fillWidth: true
                            level: 4
                            text: card.modelData.name
                            textFormat: Text.PlainText
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            text: card.modelData.description
                            wrapMode: Text.Wrap
                        }
                    }

                    QQC2.Button {
                        text: card.modelData.installed
                            ? root.l10n.i18nc("@action:button Start an installed app", "Open")
                            : root.l10n.i18nc("@action:button", "Get it from the Store")
                        icon.name: card.modelData.installed ? "system-run" : "plasmadiscover"
                        Accessible.name: card.modelData.installed
                            ? root.l10n.i18nc("@action:button %1 is an app", "Open %1", card.modelData.name)
                            : root.l10n.i18nc("@action:button %1 is an app", "Get %1 from the Store", card.modelData.name)
                        onClicked: root.store.open(card.modelData.id)
                    }
                }
            }
        }
    }
}
