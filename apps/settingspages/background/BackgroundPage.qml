// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// The desktop's picture, as Windows' Personalisation › Background offers it: a preview, the last
// five pictures to pick again, a photo of your own and how it fits the screen. Slideshows, plain
// colours and pictures from the internet stay on Plasma's own page, linked at the foot. Each change
// applies at once, to every display.

import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as Dialogs
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    readonly property DesktopBackground desktop: DesktopBackground {}
    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }
    // The fits, in Windows' order, with Plasma's FillMode for each.
    readonly property list<var> fits: [
        { text: root.l10n.i18nc("@item:inlistbox How the picture fits the screen", "Fill"), mode: DesktopBackground.Fill },
        { text: root.l10n.i18nc("@item:inlistbox How the picture fits the screen", "Fit"), mode: DesktopBackground.Fit },
        { text: root.l10n.i18nc("@item:inlistbox How the picture fits the screen", "Stretch"), mode: DesktopBackground.Stretch },
        { text: root.l10n.i18nc("@item:inlistbox How the picture fits the screen", "Tile"), mode: DesktopBackground.Tile },
        { text: root.l10n.i18nc("@item:inlistbox How the picture fits the screen", "Centre"), mode: DesktopBackground.Centre }
    ]

    // Plasma's FillMode as a QML Image's.
    function imageFill(mode: int): int {
        switch (mode) {
        case DesktopBackground.Stretch:
            return Image.Stretch;
        case DesktopBackground.Fit:
            return Image.PreserveAspectFit;
        case DesktopBackground.Tile:
            return Image.Tile;
        case DesktopBackground.Centre:
            return Image.Pad;
        default:
            return Image.PreserveAspectCrop;
        }
    }

    // Settings names the page above it, so the page's own title bar would only repeat the name.
    // System Settings has no such heading, so the title bar stays there.
    Component.onCompleted: {
        if (Qt.application.name === "orielos-settings") {
            globalToolBarStyle = Kirigami.ApplicationHeaderStyle.None;
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        // The desktop in miniature, with the picture as it fits a 16:9 screen.
        Rectangle {
            Layout.preferredWidth: Math.min(parent.width, Kirigami.Units.gridUnit * 22)
            Layout.preferredHeight: Layout.preferredWidth * 9 / 16
            radius: Kirigami.Units.cornerRadius
            color: Kirigami.Theme.alternateBackgroundColor
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
            clip: true

            Image {
                anchors.fill: parent
                anchors.margins: 1
                source: root.desktop.previewUrl(root.desktop.image, true)
                fillMode: root.imageFill(root.desktop.fillMode)
                sourceSize.width: Kirigami.Units.gridUnit * 44
                asynchronous: true
                smooth: true
                Accessible.name: root.l10n.i18nc("@info:tooltip", "Preview of the desktop picture")
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: !root.desktop.available
            type: Kirigami.MessageType.Information
            text: root.l10n.i18nc("@info", "The desktop isn't running, so the picture can't be read or changed now.")
        }

        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.largeSpacing
            level: 4
            textFormat: Text.PlainText
            visible: recentRow.count > 0
            text: root.l10n.i18nc("@title:group", "Recent images")
        }

        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                id: recentRow

                model: root.desktop.recent

                delegate: QQC2.AbstractButton {
                    id: tile

                    required property string modelData
                    readonly property bool current: modelData === root.desktop.image

                    width: Kirigami.Units.gridUnit * 6
                    height: width * 9 / 16
                    enabled: root.desktop.available
                    Accessible.name: modelData.split("/").pop()
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: current
                    QQC2.ToolTip.text: modelData.split("/").pop()
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    onClicked: root.desktop.setImage(modelData)

                    contentItem: Image {
                        source: root.desktop.previewUrl(tile.modelData, false)
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: Kirigami.Units.gridUnit * 12
                        asynchronous: true
                    }

                    background: Item {}

                    // The picture in use, and the keyboard focus, as a ring of the accent colour.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: Kirigami.Units.cornerRadius
                        color: "transparent"
                        border.width: tile.current || tile.visualFocus ? 2 : (tile.hovered ? 1 : 0)
                        border.color: tile.current || tile.visualFocus ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.4)
                    }
                }
            }
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing

            QQC2.Button {
                Kirigami.FormData.label: root.l10n.i18nc("@label", "Choose a photo:")
                text: root.l10n.i18nc("@action:button", "Browse photos")
                icon.name: "document-open"
                enabled: root.desktop.available
                onClicked: chooser.open()
            }

            QQC2.ComboBox {
                Kirigami.FormData.label: root.l10n.i18nc("@label:listbox", "Choose a fit:")
                enabled: root.desktop.available
                model: root.fits.map(fit => fit.text)
                currentIndex: Math.max(0, root.fits.findIndex(fit => fit.mode === root.desktop.fillMode))
                onActivated: index => root.desktop.setFillMode(root.fits[index].mode)
            }
        }

        // Related settings, as Windows lists them at the foot of a page.
        Kirigami.Heading {
            Layout.topMargin: Kirigami.Units.gridUnit
            level: 4
            textFormat: Text.PlainText
            text: root.l10n.i18nc("@title:group", "Related settings")
        }

        Kirigami.LinkButton {
            text: root.l10n.i18nc("@action:button A related Settings page", "Slideshows, colours and more backgrounds")
            onClicked: Qt.openUrlExternally("orielos-settings:background-more")
        }

        Kirigami.LinkButton {
            text: root.l10n.i18nc("@action:button A related Settings page", "Themes")
            onClicked: Qt.openUrlExternally("orielos-settings:themes")
        }
    }

    Dialogs.FileDialog {
        id: chooser

        title: root.l10n.i18nc("@title:window", "Choose a photo")
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        nameFilters: [root.l10n.i18nc("@item:inlistbox A kind of file", "Pictures (*.png *.jpg *.jpeg *.webp *.avif *.jxl *.bmp)")]
        onAccepted: root.desktop.setImage(selectedFile.toString())
    }
}
