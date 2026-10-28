// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami

// The rounded highlight behind a taskbar button: faint when hovered, brighter while pressed or
// while its popup is open.
Rectangle {
    property bool lit: false
    property bool hovered: false
    property bool pressed: false

    anchors.fill: parent
    radius: 6
    color: Kirigami.Theme.textColor
    opacity: pressed ? 0.14 : (lit ? 0.10 : (hovered ? 0.08 : 0))
}
