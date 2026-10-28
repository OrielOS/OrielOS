// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "button.h"
#include "decoration.h"

#include <KDecoration3/DecoratedWindow>

#include <QPainter>
#include <QVariant>

#include <cmath>

namespace OrielOSDecoration {

namespace {
// Close's red, as Windows uses it, and a little darker while pressed.
const QColor CloseHover(0xc4, 0x2b, 0x1c);
const QColor ClosePressed(0xb2, 0x27, 0x1a);
// The glyphs' size and line width, in logical pixels.
constexpr qreal GlyphSize = 10;
constexpr qreal GlyphLine = 1;
} // namespace

using KDecoration3::DecorationButtonType;

Button::Button(DecorationButtonType type, Decoration *decoration, QObject *parent)
    : DecorationButton(type, decoration, parent)
{
    connect(this, &KDecoration3::DecorationButton::hoveredChanged, this, [this]() { update(); });
    connect(this, &KDecoration3::DecorationButton::pressedChanged, this, [this]() { update(); });
}

Button::Button(QObject *parent, const QVariantList &args)
    : Button(args.at(0).value<DecorationButtonType>(), args.at(1).value<Decoration *>(), parent)
{
    setGeometry(QRectF(0, 0, Decoration::ButtonWidth, Decoration::TitleBarHeight));
}

KDecoration3::DecorationButton *Button::create(DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent)
{
    auto *d = qobject_cast<Decoration *>(decoration);
    if (!d) {
        return nullptr;
    }
    auto *button = new Button(type, d, parent);
    const auto w = d->window();
    switch (type) {
    case DecorationButtonType::Close:
        button->setVisible(w->isCloseable());
        connect(w, &KDecoration3::DecoratedWindow::closeableChanged, button, &Button::setVisible);
        break;
    case DecorationButtonType::Maximize:
        button->setVisible(w->isMaximizeable());
        connect(w, &KDecoration3::DecoratedWindow::maximizeableChanged, button, &Button::setVisible);
        break;
    case DecorationButtonType::Minimize:
        button->setVisible(w->isMinimizeable());
        connect(w, &KDecoration3::DecoratedWindow::minimizeableChanged, button, &Button::setVisible);
        break;
    case DecorationButtonType::Menu:
        break;
    default:
        // Sill's title bar has only the window menu, minimise, maximise and close.
        button->setVisible(false);
        break;
    }
    return button;
}

void Button::paint(QPainter *painter, const QRectF &repaintRegion)
{
    if (!isVisible() || !geometry().intersects(repaintRegion)) {
        return;
    }
    auto *d = qobject_cast<Decoration *>(decoration());
    if (!d) {
        return;
    }

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    const QRectF area = geometry();
    const bool close = type() == DecorationButtonType::Close;

    if (isHovered() || isPressed()) {
        QColor fill;
        if (close) {
            fill = isPressed() ? ClosePressed : CloseHover;
        } else {
            fill = d->window()->palette().color(QPalette::Active, QPalette::WindowText);
            fill.setAlphaF(isPressed() ? 0.12 : 0.08);
        }
        painter->fillRect(area, fill);
    }

    if (type() == DecorationButtonType::Menu) {
        const QRectF iconRect(area.center() - QPointF(8, 8), QSizeF(16, 16));
        d->window()->icon().paint(painter, iconRect.toRect(), Qt::AlignCenter, d->window()->isActive() ? QIcon::Normal : QIcon::Disabled);
    } else {
        QPen pen(close && (isHovered() || isPressed()) ? QColor(Qt::white) : d->foregroundColor());
        pen.setWidthF(GlyphLine);
        pen.setCapStyle(Qt::FlatCap);
        pen.setJoinStyle(Qt::MiterJoin);
        painter->setPen(pen);
        painter->setBrush(Qt::NoBrush);
        // Centred on a half pixel, so one-pixel lines stay sharp.
        const QPointF origin(std::round(area.center().x() - GlyphSize / 2) + 0.5, std::round(area.center().y() - GlyphSize / 2) + 0.5);
        paintGlyph(painter, QRectF(origin, QSizeF(GlyphSize - 1, GlyphSize - 1)));
    }
    painter->restore();
}

void Button::paintGlyph(QPainter *painter, const QRectF &box) const
{
    switch (type()) {
    case DecorationButtonType::Minimize:
        // On the half pixel, like the box's edges, so the line stays one pixel thick.
        painter->drawLine(QPointF(box.left(), box.top() + std::floor(box.height() / 2)), QPointF(box.right(), box.top() + std::floor(box.height() / 2)));
        break;
    case DecorationButtonType::Maximize:
        if (isChecked()) {
            // Restore: a smaller square, with the edge of another behind it.
            const qreal step = 2;
            painter->drawRoundedRect(QRectF(box.left(), box.top() + step, box.width() - step, box.height() - step), 1, 1);
            QPolygonF back;
            back << QPointF(box.left() + step, box.top() + step) << QPointF(box.left() + step, box.top()) << QPointF(box.right(), box.top())
                 << QPointF(box.right(), box.bottom() - step) << QPointF(box.right() - step, box.bottom() - step);
            painter->drawPolyline(back);
        } else {
            painter->drawRoundedRect(box, 1, 1);
        }
        break;
    case DecorationButtonType::Close:
        painter->drawLine(box.topLeft(), box.bottomRight());
        painter->drawLine(box.topRight(), box.bottomLeft());
        break;
    default:
        break;
    }
}

} // namespace OrielOSDecoration
