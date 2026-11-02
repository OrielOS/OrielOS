// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Settings › Devices › Camera, as Windows' Cameras page: the cameras connected, a live picture from
// the one chosen, and its brightness where the camera allows it. The camera is in use only while
// the page shows it.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtMultimedia
import org.kde.kcmutils as KCM
import org.kde.ki18n
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    // Settings' engine doesn't set up the KI18n singleton, and the page's strings are in its own
    // translation domain.
    readonly property KI18nContext l10n: KI18nContext {
        translationDomain: "orielos-settings-pages"
    }
    readonly property bool hasCamera: devices.videoInputs.length > 0

    MediaDevices {
        id: devices
    }

    CaptureSession {
        camera: Camera {
            id: camera

            cameraDevice: root.hasCamera ? devices.videoInputs[Math.max(0, chooser.currentIndex)] : devices.defaultVideoInput
            active: root.hasCamera && root.visible
        }
        videoOutput: preview
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit * 4
            visible: !root.hasCamera
            icon.name: "camera-web"
            text: root.l10n.i18nc("@info", "No camera found")
            explanation: root.l10n.i18nc("@info", "Connect a camera, or check that the laptop's camera isn't turned off with a switch or key.")
        }

        QQC2.ComboBox {
            id: chooser

            Layout.fillWidth: true
            visible: root.hasCamera
            model: devices.videoInputs
            textRole: "description"
            Accessible.name: root.l10n.i18nc("@label:listbox", "Camera")
        }

        VideoOutput {
            id: preview

            Layout.fillWidth: true
            Layout.preferredHeight: width * 9 / 16
            visible: root.hasCamera
            fillMode: VideoOutput.PreserveAspectFit
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: root.hasCamera && camera.error !== Camera.NoError
            text: root.l10n.i18nc("@info %1 is the reason", "The camera can't be shown: %1", camera.errorString)
            wrapMode: Text.Wrap
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            visible: root.hasCamera && (camera.supportedFeatures & Camera.ExposureCompensation) !== 0

            QQC2.Slider {
                Kirigami.FormData.label: root.l10n.i18nc("@label:slider", "Brightness:")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                from: -2
                to: 2
                stepSize: 0.5
                value: camera.exposureCompensation
                onMoved: camera.exposureCompensation = value
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: root.hasCamera
            text: root.l10n.i18nc("@info", "Which apps may use the camera is under Privacy & security › App permissions.")
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
        }
    }
}
