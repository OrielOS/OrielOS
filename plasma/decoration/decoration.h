// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationButtonGroup>

#include <QColor>
#include <QPainterPath>
#include <QVariant>

namespace OrielOSDecoration {

/**
 * OrielOS's window frame, in Sill's look: a flat title bar in the window's colour with the app's
 * icon and title on the left and wide, flat minimise, maximise and close buttons on the right,
 * rounded corners, a hairline outline and a soft shadow. Maximised windows lose the corners.
 * The window in use has a Mica title bar: a little see-through, over KWin's blur, so the wallpaper
 * faintly tints it; it turns flat when the window isn't in use or transparency effects are off.
 */
class Decoration : public KDecoration3::Decoration
{
    Q_OBJECT

public:
    explicit Decoration(QObject *parent = nullptr, const QVariantList &args = QVariantList());

    bool init() override;
    void paint(QPainter *painter, const QRectF &repaintRegion) override;

    // The title bar's colours, which the buttons follow.
    QColor titleBarColor() const;
    QColor foregroundColor() const;

    // Sill's measurements, in logical pixels.
    static constexpr qreal TitleBarHeight = 40;
    static constexpr qreal ButtonWidth = 46;
    static constexpr qreal CornerRadius = 8;

private:
    bool isMaximized() const;
    // Whether the title bar is see-through now.
    bool isMica() const;
    QPainterPath titleBarShape() const;
    void readTransparency();
    void updateBlur();
    void updateBorders();
    void updateTitleBar();
    void updateButtons();
    void updateShadow();

    KDecoration3::DecorationButtonGroup *m_leftButtons = nullptr;
    KDecoration3::DecorationButtonGroup *m_rightButtons = nullptr;
    // Settings › Personalisation › Colours › Transparency effects, KWin's blur.
    bool m_transparency = true;
};

} // namespace OrielOSDecoration
