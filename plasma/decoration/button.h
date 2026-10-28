// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KDecoration3/DecorationButton>

#include <QVariant>

namespace OrielOSDecoration {

class Decoration;

/**
 * A title bar button in Sill's look: a flat, full-height area, lit faintly when hovered and a little
 * more when pressed, with a thin line glyph; Close turns red when hovered. The window menu button
 * shows the app's icon.
 */
class Button : public KDecoration3::DecorationButton
{
    Q_OBJECT

public:
    explicit Button(KDecoration3::DecorationButtonType type, Decoration *decoration, QObject *parent = nullptr);
    // The form KDecoration's plugin loader uses.
    explicit Button(QObject *parent, const QVariantList &args);

    static KDecoration3::DecorationButton *create(KDecoration3::DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent);

    void paint(QPainter *painter, const QRectF &repaintRegion) override;

private:
    void paintGlyph(QPainter *painter, const QRectF &box) const;
};

} // namespace OrielOSDecoration
