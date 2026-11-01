// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The installed fonts, as Windows' Personalisation › Fonts shows them: a place to drop font files
// to install them, a search, and each family with a sample in its own font.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as Dialogs
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.GridViewKCM {
    id: root

    readonly property FontLibrary library: FontLibrary {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }
    readonly property var shownFamilies: {
        const words = search.text.trim().toLowerCase();
        return root.library.families.filter(family => words.length === 0 || String(family.name).toLowerCase().includes(words));
    }
    // What the last install did, for the message above the fonts.
    property string result: ""
    property bool resultIsError: false

    function install(urls: list<url>) {
        const done = root.library.install(urls);
        const parts = [];
        if (done.installed.length > 0) {
            parts.push(root.l10n.i18nc("@info %1 is a list of font file names", "Installed %1. Apps show new fonts the next time they open.", done.installed.join(", ")));
        }
        if (done.existing.length > 0) {
            parts.push(root.l10n.i18nc("@info %1 is a list of font file names", "Already installed: %1.", done.existing.join(", ")));
        }
        if (done.unsupported.length > 0) {
            parts.push(root.l10n.i18nc("@info %1 is a list of file names", "Not a font OrielOS can install: %1.", done.unsupported.join(", ")));
        }
        root.result = parts.join(" ");
        root.resultIsError = done.installed.length === 0;
    }

    // Settings names the page above it, so the page's own title bar would only repeat the name.
    // System Settings has no such heading, so the title bar stays there.
    Component.onCompleted: {
        if (Qt.application.name === "orielos-settings") {
            globalToolBarStyle = Kirigami.ApplicationHeaderStyle.None;
        }
    }

    header: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            level: 4
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@title:group", "Add fonts")
        }

        // Windows' dashed drop zone, which also opens a file chooser.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 5
            radius: Kirigami.Units.cornerRadius
            color: drop.containsDrag ? Qt.alpha(Kirigami.Theme.highlightColor, 0.15) : "transparent"
            border.width: 1
            border.color: drop.containsDrag ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.35)

            DropArea {
                id: drop

                anchors.fill: parent
                keys: ["text/uri-list"]
                onDropped: event => {
                    root.install(event.urls);
                    event.acceptProposedAction();
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    Layout.alignment: Qt.AlignHCenter
                    textFormat: Text.PlainText
                    text: root.l10n.i18nc("@info", "Drag and drop to install")
                }

                QQC2.Button {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.l10n.i18nc("@action:button", "Browse and install fonts…")
                    icon.name: "document-open"
                    onClicked: chooser.open()
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.result.length > 0
            type: root.resultIsError ? Kirigami.MessageType.Warning : Kirigami.MessageType.Positive
            text: root.result
            showCloseButton: true
            onVisibleChanged: {
                if (!visible) {
                    root.result = "";
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                textFormat: Text.PlainText
                text: root.l10n.i18nc("@title:group %1 is how many font families there are", "Available fonts (%1)", root.library.families.length)
            }

            Kirigami.SearchField {
                id: search

                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                placeholderText: root.l10n.i18nc("@info:placeholder", "Type here to search")
            }
        }
    }

    view.model: root.shownFamilies
    view.implicitCellWidth: Kirigami.Units.gridUnit * 11
    view.implicitCellHeight: Kirigami.Units.gridUnit * 7

    view.delegate: KCM.GridDelegate {
        id: family

        required property var modelData

        text: String(family.modelData.name)
        subtitle: root.l10n.i18ncp("@info", "%1 font face", "%1 font faces", Number(family.modelData.faces))
        toolTip: text
        thumbnailAvailable: true

        thumbnail: QQC2.Label {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@info A sample of a font", "The quick brown fox jumps over the lazy dog.")
            font.family: family.modelData.name
            font.pointSize: 13
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
        }
    }

    footer: ColumnLayout {
        // Related settings, as Windows lists them at the foot of a page.
        Kirigami.LinkButton {
            text: root.l10n.i18nc("@action:button A related Settings page", "Fonts used by apps and the desktop")
            onClicked: Qt.openUrlExternally("orielos-settings:kcm_fonts")
        }
    }

    Dialogs.FileDialog {
        id: chooser

        title: root.l10n.i18nc("@title:window", "Install fonts")
        fileMode: Dialogs.FileDialog.OpenFiles
        nameFilters: [root.l10n.i18nc("@item:inlistbox A file type", "Font files (*.ttf *.otf *.ttc *.otc)")]
        onAccepted: root.install(chooser.selectedFiles)
    }
}
