// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

// Set up this PC: six short steps after the first sign-in. Light or dark, where the taskbar's apps
// sit, the update channel, the game stores, the graphics card's driver, and where things are. Each
// choice changes the real setting at once, through the same code as Settings; Skip the rest, Done
// and closing the window all end it.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.orielos.accessories
import org.orielos.taskbar
import org.orielos.tour
import org.orielos.updatesettings

QQC2.ApplicationWindow {
    id: root

    property int current: 0
    readonly property list<string> stepNames: [
        KI18n.i18nc("@title A step of the tour", "Light or dark"),
        KI18n.i18nc("@title A step of the tour", "Taskbar"),
        KI18n.i18nc("@title A step of the tour", "Updates"),
        KI18n.i18nc("@title A step of the tour", "Games"),
        KI18n.i18nc("@title A step of the tour", "Graphics"),
        KI18n.i18nc("@title A step of the tour", "Where things are"),
    ]
    readonly property bool lastStep: current === stepNames.length - 1

    readonly property Appearance appearance: Appearance {}
    readonly property TaskbarOptions taskbar: TaskbarOptions {}
    readonly property UpdateSettings updates: UpdateSettings {}
    readonly property StoreApps stores: StoreApps {
        collection: "games"
    }
    readonly property GraphicsCard card: GraphicsCard {}

    // OrielOS's wallpaper, which the miniature desktop shows: Daybreak in light, Nightfall in dark.
    readonly property url wallpaperLight: "file:///usr/share/wallpapers/OrielOS/contents/images/3840x2160.jpg"
    readonly property url wallpaperDark: "file:///usr/share/wallpapers/OrielOS/contents/images_dark/3840x2160.jpg"

    function go(step: int): void {
        root.current = Math.max(0, Math.min(root.stepNames.length - 1, step));
    }

    title: KI18n.i18nc("@title:window", "Set up this PC")
    width: Kirigami.Units.gridUnit * 49
    height: Kirigami.Units.gridUnit * 33
    minimumWidth: Kirigami.Units.gridUnit * 40
    minimumHeight: Kirigami.Units.gridUnit * 30
    color: Kirigami.Theme.backgroundColor

    // A screen reader hears each step's name as it opens.
    onCurrentChanged: page.Accessible.announce(KI18n.i18nc("@info:accessibility %1 is a step's name, %2 its number and %3 how many there are",
        "%1, step %2 of %3", root.stepNames[root.current], root.current + 1, root.stepNames.length))
    Component.onCompleted: nextButton.forceActiveFocus()

    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: root.close()
    }

    // Keyboard focus: a ring 2 px outside the control, as Sill draws it.
    component FocusRing: Rectangle {
        property bool shown: false
        // The control's own corner radius.
        property real baseRadius: Kirigami.Units.cornerRadius

        anchors.fill: parent
        anchors.margins: -4
        visible: shown
        radius: baseRadius + 4
        color: "transparent"
        border.width: 2
        border.color: Kirigami.Theme.focusColor
    }

    // The step's main action, filled with the accent as in Sill: Next, then Done.
    component PrimaryButton: QQC2.Button {
        id: primary

        Kirigami.Theme.colorSet: Kirigami.Theme.Button
        Kirigami.Theme.inherit: false
        leftPadding: Kirigami.Units.gridUnit
        rightPadding: Kirigami.Units.gridUnit
        font.weight: Font.Medium

        background: Rectangle {
            implicitHeight: Kirigami.Units.gridUnit * 2
            implicitWidth: Kirigami.Units.gridUnit * 4
            radius: Kirigami.Units.cornerRadius
            color: primary.down ? Qt.darker(Kirigami.Theme.highlightColor, 1.35)
                : primary.hovered ? Qt.darker(Kirigami.Theme.highlightColor, 1.12) : Kirigami.Theme.highlightColor

            FocusRing {
                shown: primary.visualFocus
            }
        }

        contentItem: QQC2.Label {
            text: primary.text
            font: primary.font
            color: Kirigami.Theme.highlightedTextColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // A step in the rail: ticked once passed, blue while open.
    component StepButton: QQC2.AbstractButton {
        id: step

        required property int index
        required property string modelData
        readonly property bool isCurrent: index === root.current
        readonly property bool done: index < root.current

        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 2
        activeFocusOnTab: true
        text: modelData
        leftPadding: Kirigami.Units.smallSpacing * 2
        rightPadding: Kirigami.Units.smallSpacing * 2
        Accessible.role: Accessible.PageTab
        Accessible.name: isCurrent ? KI18n.i18nc("@info:accessibility %1 is a step's name", "%1, open", modelData)
            : done ? KI18n.i18nc("@info:accessibility %1 is a step's name", "%1, done", modelData) : modelData
        onClicked: root.go(index)

        background: Rectangle {
            Kirigami.Theme.colorSet: Kirigami.Theme.View
            Kirigami.Theme.inherit: false
            radius: Kirigami.Units.cornerRadius
            color: step.isCurrent ? Kirigami.Theme.backgroundColor
                : step.hovered ? Qt.alpha(Kirigami.Theme.textColor, 0.05) : "transparent"
            border.width: step.isCurrent ? 1 : 0
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.08)

            FocusRing {
                shown: step.visualFocus
            }
        }

        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing

            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit + Kirigami.Units.smallSpacing / 2
                implicitHeight: implicitWidth
                radius: width / 2
                color: step.isCurrent ? Kirigami.Theme.highlightColor : step.done ? Kirigami.Theme.textColor : "transparent"
                border.width: step.isCurrent || step.done ? 0 : 1
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.24)

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.small - Kirigami.Units.smallSpacing
                    height: width
                    visible: step.done
                    source: "checkmark"
                    isMask: true
                    color: Kirigami.Theme.backgroundColor
                }

                QQC2.Label {
                    anchors.centerIn: parent
                    visible: !step.done
                    text: step.index + 1
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    font.features: { "tnum": 1 }
                    color: step.isCurrent ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.disabledTextColor
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: step.modelData
                elide: Text.ElideRight
                color: step.isCurrent ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
            }
        }
    }

    // A step's heading and what it's about.
    component StepHeading: ColumnLayout {
        id: heading

        property string title
        property string text

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing * 2

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 1
            text: heading.title
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.85
            font.weight: Font.DemiBold
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 29
            Layout.bottomMargin: Kirigami.Units.gridUnit
            text: heading.text
            wrapMode: Text.Wrap
            color: Kirigami.Theme.disabledTextColor
        }
    }

    // One of a step's choices, which applies as soon as it's picked; a picture above it when it has
    // one.
    component Choice: QQC2.AbstractButton {
        id: choice

        property bool selected: false
        property Component picture: null
        property string note: ""

        Layout.fillWidth: true
        activeFocusOnTab: true
        padding: Kirigami.Units.smallSpacing * 2
        Accessible.role: Accessible.RadioButton
        Accessible.checkable: true
        Accessible.checked: selected
        Accessible.name: text
        Accessible.description: note

        background: Rectangle {
            radius: Kirigami.Units.cornerRadius * 2
            color: Kirigami.Theme.backgroundColor
            border.width: choice.selected ? 2 : 1
            border.color: choice.selected ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, choice.hovered ? 0.3 : 0.14)

            FocusRing {
                shown: choice.visualFocus
                baseRadius: Kirigami.Units.cornerRadius * 2
            }
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 10
                visible: choice.picture !== null
                active: visible
                sourceComponent: choice.picture
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: choice.picture ? Kirigami.Units.smallSpacing : 0
                spacing: Kirigami.Units.smallSpacing * 2

                Rectangle {
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: implicitWidth
                    radius: width / 2
                    color: "transparent"
                    border.width: choice.selected ? 5 : 1
                    border.color: choice.selected ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.4)
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: choice.text
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                visible: choice.note.length > 0
                text: choice.note
                wrapMode: Text.Wrap
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.disabledTextColor
            }
        }
    }

    // This PC's desktop in miniature: the wallpaper, a window and the taskbar, with the sill under
    // the open app.
    component Miniature: Item {
        id: mini

        property bool dark: true
        property bool centred: true

        clip: true

        Image {
            anchors.fill: parent
            source: mini.dark ? root.wallpaperDark : root.wallpaperLight
            sourceSize.width: 480
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        Rectangle {
            x: parent.width * 0.18
            y: parent.height * 0.16
            width: parent.width * 0.52
            height: parent.height * 0.52
            radius: 3
            color: mini.dark ? "#1b2440" : "#f4f6fb"
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 16
            color: mini.dark ? Qt.rgba(0.05, 0.08, 0.19, 0.8) : Qt.rgba(0.96, 0.96, 0.98, 0.85)

            Row {
                x: mini.centred ? (parent.width - width) / 2 : 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                    model: 5

                    Rectangle {
                        id: app

                        required property int index

                        width: 9
                        height: 9
                        radius: 2
                        color: mini.dark ? "#c9d6f5" : "#5b6478"

                        Rectangle {
                            visible: app.index === 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: 2
                            width: 7
                            height: 2
                            radius: 1
                            color: "#ffb547"
                        }
                    }
                }
            }
        }
    }

    // A line in a step's list: an icon, a name and a detail, and whatever goes at its end.
    component ListRow: QQC2.Control {
        id: row

        property string iconSource
        property bool iconMask: false
        property string title
        property string detail
        default property alias trailing: end.data

        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 31
        topPadding: Kirigami.Units.largeSpacing
        bottomPadding: Kirigami.Units.largeSpacing
        leftPadding: Kirigami.Units.gridUnit
        rightPadding: Kirigami.Units.gridUnit
        Accessible.role: Accessible.ListItem
        Accessible.name: title
        Accessible.description: detail

        background: Rectangle {
            radius: Kirigami.Units.cornerRadius * 2
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.14)
        }

        contentItem: RowLayout {
            spacing: Kirigami.Units.gridUnit

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                source: row.iconSource
                fallback: "application-x-executable"
                isMask: row.iconMask
                color: Kirigami.Theme.disabledTextColor
                Accessible.ignored: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                QQC2.Label {
                    Layout.fillWidth: true
                    text: row.title
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    visible: row.detail.length > 0
                    text: row.detail
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: Kirigami.Theme.disabledTextColor
                }
            }

            RowLayout {
                id: end

                spacing: Kirigami.Units.smallSpacing
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // The steps.
        ColumnLayout {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 13
            Layout.fillWidth: false
            Layout.fillHeight: true
            Layout.margins: Kirigami.Units.gridUnit
            Layout.rightMargin: Kirigami.Units.largeSpacing
            spacing: 2

            Kirigami.Heading {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.largeSpacing
                level: 5
                font.weight: Font.DemiBold
                text: KI18n.i18nc("@title The tour's list of steps", "A few choices")
                color: Kirigami.Theme.disabledTextColor
            }

            Repeater {
                model: root.stepNames

                delegate: StepButton {}
            }

            Item {
                Layout.fillHeight: true
            }
        }

        Kirigami.Separator {
            Layout.fillHeight: true
        }

        // The open step and the buttons under it.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Kirigami.Theme.colorSet: Kirigami.Theme.View
            Kirigami.Theme.inherit: false
            color: Kirigami.Theme.backgroundColor

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                QQC2.ScrollView {
                    id: scroller

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                    Item {
                        implicitWidth: scroller.availableWidth
                        implicitHeight: page.implicitHeight + Kirigami.Units.gridUnit * 4

                        Loader {
                            id: page

                            x: Kirigami.Units.gridUnit * 2
                            y: Kirigami.Units.gridUnit * 2
                            width: parent.width - Kirigami.Units.gridUnit * 4
                            sourceComponent: [lightOrDark, taskbarStep, updatesStep, gamesStep, graphicsStep, whereThingsAre][root.current]
                        }
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3.5
                    Layout.leftMargin: Kirigami.Units.gridUnit * 2
                    Layout.rightMargin: Kirigami.Units.gridUnit + Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing * 2

                    QQC2.Button {
                        visible: !root.lastStep
                        flat: true
                        text: KI18n.i18nc("@action:button Ends the tour", "Skip the rest")
                        onClicked: root.close()
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    QQC2.Label {
                        text: KI18n.i18nc("@info %1 is the open step's number, %2 how many there are", "%1 of %2", root.current + 1, root.stepNames.length)
                        font.features: { "tnum": 1 }
                        color: Kirigami.Theme.disabledTextColor
                    }

                    QQC2.Button {
                        // Hidden on the first step without moving the others.
                        opacity: root.current > 0 ? 1 : 0
                        enabled: root.current > 0
                        text: KI18n.i18nc("@action:button", "Back")
                        onClicked: root.go(root.current - 1)
                    }

                    PrimaryButton {
                        id: nextButton

                        text: root.lastStep ? KI18n.i18nc("@action:button Ends the tour", "Done") : KI18n.i18nc("@action:button", "Next")
                        onClicked: root.lastStep ? root.close() : root.go(root.current + 1)
                    }
                }
            }
        }
    }

    Component {
        id: lightOrDark

        ColumnLayout {
            spacing: 0

            StepHeading {
                title: KI18n.i18nc("@title", "Light or dark")
                text: KI18n.i18nc("@info", "How windows, Start and the taskbar look. Settings › Personalisation › Themes changes it later, and Accent colour, next to it, picks the colour of highlights.")
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Kirigami.Units.gridUnit
                uniformCellWidths: true
                enabled: !root.appearance.busy
                Accessible.role: Accessible.Grouping
                Accessible.name: KI18n.i18nc("@title:group", "Colours")

                Choice {
                    text: KI18n.i18nc("@option:radio", "Light")
                    selected: !root.appearance.dark
                    picture: Miniature {
                        dark: false
                        centred: root.taskbar.centred
                    }
                    onClicked: root.appearance.dark = false
                }

                Choice {
                    text: KI18n.i18nc("@option:radio", "Dark")
                    selected: root.appearance.dark
                    picture: Miniature {
                        dark: true
                        centred: root.taskbar.centred
                    }
                    onClicked: root.appearance.dark = true
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.gridUnit
                type: Kirigami.MessageType.Error
                text: root.appearance.error
                visible: text.length > 0
            }
        }
    }

    Component {
        id: taskbarStep

        ColumnLayout {
            spacing: 0

            StepHeading {
                title: KI18n.i18nc("@title", "Where the taskbar's apps sit")
                text: KI18n.i18nc("@info", "In the middle, with Start first, or along the left. Settings › Personalisation › Taskbar has the rest of its settings.")
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Kirigami.Units.gridUnit
                uniformCellWidths: true
                visible: root.taskbar.available && root.taskbar.canAlign
                Accessible.role: Accessible.Grouping
                Accessible.name: KI18n.i18nc("@title:group", "Taskbar alignment")

                Choice {
                    text: KI18n.i18nc("@option:radio The taskbar's alignment", "Centre")
                    selected: root.taskbar.centred
                    picture: Miniature {
                        dark: root.appearance.dark
                        centred: true
                    }
                    onClicked: root.taskbar.centred = true
                }

                Choice {
                    text: KI18n.i18nc("@option:radio The taskbar's alignment", "Left")
                    selected: !root.taskbar.centred
                    picture: Miniature {
                        dark: root.appearance.dark
                        centred: false
                    }
                    onClicked: root.taskbar.centred = false
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                type: Kirigami.MessageType.Information
                text: KI18n.i18nc("@info", "This taskbar has been rearranged, so its apps can't be moved from here.")
                visible: root.taskbar.ready && !(root.taskbar.available && root.taskbar.canAlign)
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.gridUnit
                type: Kirigami.MessageType.Error
                text: root.taskbar.error
                visible: text.length > 0
            }
        }
    }

    Component {
        id: updatesStep

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing * 2

            StepHeading {
                title: KI18n.i18nc("@title", "Which updates this PC gets")
                text: KI18n.i18nc("@info", "OrielOS updates itself in the background and asks before restarting. Your apps from the Store update the same way.")
            }

            ColumnLayout {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 31
                spacing: Kirigami.Units.smallSpacing * 2
                enabled: !root.updates.busy
                Accessible.role: Accessible.Grouping
                Accessible.name: KI18n.i18nc("@title:group", "Update channel")

                Choice {
                    text: KI18n.i18nc("@option:radio An update channel", "Stable")
                    note: KI18n.i18nc("@info", "Versions that people have already used on the testing channel. Best for most people.")
                    selected: root.updates.channel === 0
                    onClicked: root.updates.setChannel(0)
                }

                Choice {
                    text: KI18n.i18nc("@option:radio An update channel", "Testing")
                    note: KI18n.i18nc("@info", "Every new version as soon as it's built, a few days sooner and less tested.")
                    selected: root.updates.channel === 1
                    onClicked: root.updates.setChannel(1)
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: KI18n.i18nc("@info", "Changing the channel needs an administrator's password.")
                wrapMode: Text.Wrap
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.disabledTextColor
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                type: Kirigami.MessageType.Error
                text: root.updates.error
                visible: text.length > 0
            }
        }
    }

    Component {
        id: gamesStep

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing * 2

            StepHeading {
                title: KI18n.i18nc("@title", "Get your games")
                text: KI18n.i18nc("@info", "Steam and the other game stores install from the Store. Sign in and your library is there; Windows games run through Proton.")
            }

            Repeater {
                model: root.stores.apps

                delegate: ListRow {
                    id: storeRow

                    required property var modelData

                    iconSource: modelData.icon
                    title: modelData.name
                    detail: modelData.description

                    QQC2.Button {
                        text: storeRow.modelData.installed ? KI18n.i18nc("@action:button Starts an installed app", "Open")
                            : KI18n.i18nc("@action:button Opens an app's page in the Store", "Get")
                        Accessible.name: storeRow.modelData.installed ? KI18n.i18nc("@action:button %1 is an app", "Open %1", storeRow.modelData.name)
                            : KI18n.i18nc("@action:button %1 is an app", "Get %1 from the Store", storeRow.modelData.name)
                        onClicked: root.stores.open(storeRow.modelData.id)
                    }
                }
            }
        }
    }

    Component {
        id: graphicsStep

        ColumnLayout {
            readonly property bool working: root.card.state === GraphicsCard.Working

            spacing: Kirigami.Units.smallSpacing * 2

            StepHeading {
                title: !root.card.available ? KI18n.i18nc("@title", "Graphics")
                    : root.card.state === GraphicsCard.Working ? KI18n.i18nc("@title", "Your graphics card is ready")
                    : root.card.keyPending ? KI18n.i18nc("@title", "One restart to finish the graphics driver")
                    : root.card.state === GraphicsCard.BasicDriver ? KI18n.i18nc("@title", "Your graphics card is on a basic driver")
                    : KI18n.i18nc("@title", "Your graphics card has no driver")
                text: !root.card.available ? KI18n.i18nc("@info", "OrielOS found no graphics card to set up.")
                    : root.card.state !== GraphicsCard.Working && root.card.keyPending ? KI18n.i18nc("@info", "The driver starts once this PC trusts it. The next restart shows a blue screen: press a key, choose Enroll MOK, then Continue, then Yes, type the password orielos, then choose Reboot.")
                    : root.card.state !== GraphicsCard.Working ? KI18n.i18nc("@info", "Games may run slowly until it's fixed. Device security in Settings says what's wrong and how to fix it.")
                    : root.card.vendor === "nvidia" ? KI18n.i18nc("@info", "OrielOS comes with NVIDIA's driver, so games and the desktop use the card from the start.")
                    : KI18n.i18nc("@info", "Its driver is part of Linux itself, so games and the desktop use the card from the start.")
            }

            ListRow {
                visible: root.card.available
                iconSource: "video-display"
                iconMask: true
                title: root.card.name
                detail: root.card.driverVersion.length > 0 ? KI18n.i18nc("@info %1 is a driver's version", "Driver %1", root.card.driverVersion)
                    : root.card.driver.length > 0 ? KI18n.i18nc("@info %1 is a driver's name, such as amdgpu", "Driver: %1", root.card.driver) : ""

                Rectangle {
                    implicitWidth: Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    radius: width / 2
                    color: root.card.state === GraphicsCard.Working ? Kirigami.Theme.positiveTextColor
                        : root.card.state === GraphicsCard.BasicDriver ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor
                }

                QQC2.Label {
                    text: root.card.state === GraphicsCard.Working ? KI18n.i18nc("@info The graphics card's state", "Working")
                        : root.card.state === GraphicsCard.BasicDriver ? KI18n.i18nc("@info The graphics card's state", "Basic driver")
                        : KI18n.i18nc("@info The graphics card's state", "No driver")
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: root.card.state === GraphicsCard.Working ? Kirigami.Theme.positiveTextColor
                        : root.card.state === GraphicsCard.BasicDriver ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor
                }
            }

            ListRow {
                visible: root.card.vendor === "nvidia" && root.card.state === GraphicsCard.Working
                iconSource: "settings-configure"
                iconMask: true
                title: KI18n.i18nc("@title", "NVIDIA's own settings")
                detail: KI18n.i18nc("@info", "Screens, colour and 3D settings")

                QQC2.Button {
                    text: KI18n.i18nc("@action:button", "Open")
                    Accessible.name: KI18n.i18nc("@action:button", "Open NVIDIA's own settings")
                    onClicked: Qt.openUrlExternally("orielos-settings:nvidia")
                }
            }

            ListRow {
                visible: root.card.available && root.card.state !== GraphicsCard.Working && !root.card.keyPending
                iconSource: "security-medium"
                iconMask: true
                title: KI18n.i18nc("@title", "Device security")
                detail: KI18n.i18nc("@info", "What's wrong with the driver, and how to fix it")

                QQC2.Button {
                    text: KI18n.i18nc("@action:button", "Open")
                    Accessible.name: KI18n.i18nc("@action:button", "Open Device security")
                    onClicked: Qt.openUrlExternally("orielos-settings:device-security")
                }
            }
        }
    }

    Component {
        id: whereThingsAre

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing * 2

            StepHeading {
                title: KI18n.i18nc("@title", "Where to find things")
                text: KI18n.i18nc("@info", "Everything here can be changed again later.")
            }

            ListRow {
                iconSource: "orielos-start"
                title: KI18n.i18nc("@title", "Start")
                detail: KI18n.i18nc("@info", "Your apps, search and power. Press the Windows key")
            }

            ListRow {
                iconSource: "preferences-system"
                title: KI18n.i18nc("@title", "Settings")
                detail: KI18n.i18nc("@info", "Everything about this PC. Windows + I")

                QQC2.Button {
                    text: KI18n.i18nc("@action:button", "Open")
                    Accessible.name: KI18n.i18nc("@action:button", "Open Settings")
                    onClicked: Launcher.openApp("org.orielos.Settings")
                }
            }

            ListRow {
                iconSource: "plasmadiscover"
                title: KI18n.i18nc("@title", "Store")
                detail: KI18n.i18nc("@info", "Apps and games, all from Flathub")

                QQC2.Button {
                    text: KI18n.i18nc("@action:button", "Open")
                    Accessible.name: KI18n.i18nc("@action:button", "Open the Store")
                    onClicked: Launcher.openApp("org.kde.discover")
                }
            }

            ListRow {
                iconSource: "preferences-desktop"
                title: KI18n.i18nc("@title", "This tour")
                detail: KI18n.i18nc("@info", "Start › All apps › Set up this PC")
            }
        }
    }
}
