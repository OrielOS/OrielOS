// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// Which apps used the camera, the microphone and the location in the last seven days, as Windows'
// privacy pages list them under Recent activity. The list is kept on this computer only.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property RecentActivity activity: RecentActivity {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }

    // Settings names the page above it, so the page's own title bar would only repeat the name.
    // System Settings has no such heading, so the title bar stays there.
    Component.onCompleted: {
        if (Qt.application.name === "orielos-settings") {
            globalToolBarStyle = Kirigami.ApplicationHeaderStyle.None;
        }
    }

    component Section: ColumnLayout {
        id: section

        required property string title
        required property string empty
        required property var apps

        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            level: 4
            textFormat: Text.PlainText
            text: section.title
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: section.apps.length === 0
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            opacity: 0.7
            text: section.empty
        }

        Repeater {
            model: section.apps

            delegate: RowLayout {
                id: row

                required property var modelData

                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                    source: row.modelData.icon
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: row.modelData.name
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font: Kirigami.Theme.smallFont
                        color: row.modelData.inUse ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                        text: row.modelData.when
                    }
                }
            }
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@info", "Apps that used the camera, the microphone or this computer's location in the last 7 days. This list stays on this computer.")
        }

        Section {
            title: root.l10n.i18nc("@title:group", "Camera")
            empty: root.l10n.i18nc("@info", "No app has used the camera in the last 7 days.")
            apps: root.activity.camera
        }

        Section {
            title: root.l10n.i18nc("@title:group", "Microphone")
            empty: root.l10n.i18nc("@info", "No app has used the microphone in the last 7 days.")
            apps: root.activity.microphone
        }

        Section {
            title: root.l10n.i18nc("@title:group", "Location")
            empty: root.l10n.i18nc("@info", "No app has used this computer's location in the last 7 days.")
            apps: root.activity.location
        }

        // Related settings, as Windows lists them at the foot of a page.
        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.gridUnit
            level: 4
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@title:group", "Related settings")
        }

        Kirigami.LinkButton {
            text: root.l10n.i18nc("@action:button A related Settings page", "App permissions")
            onClicked: Qt.openUrlExternally("orielos-settings:app-permissions")
        }
    }
}
