// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationButtonGroup>

#include <QColor>
#include <QVariant>

namespace OrielOSDecoration {

/**
 * OrielOS's window frame, in Sill's look: a flat title bar in the window's colour with the app's
 * icon and title on the left and wide, flat minimise, maximise and close buttons on the right,
 * rounded corners, a hairline outline and a soft shadow. Maximised windows lose the corners.
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
    void updateBorders();
    void updateTitleBar();
    void updateButtons();
    void updateShadow();

    KDecoration3::DecorationButtonGroup *m_leftButtons = nullptr;
    KDecoration3::DecorationButtonGroup *m_rightButtons = nullptr;
};

} // namespace OrielOSDecoration
