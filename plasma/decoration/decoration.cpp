// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "decoration.h"
#include "button.h"
#include "shadow.h"

#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/DecorationSettings>
#include <KDecoration3/ScaleHelpers>
#include <KConfigGroup>
#include <KPluginFactory>
#include <KSharedConfig>

#include <QPainter>
#include <QRegion>

K_PLUGIN_FACTORY_WITH_JSON(OrielOSDecorationFactory, "orielos.json", registerPlugin<OrielOSDecoration::Decoration>();
    registerPlugin<OrielOSDecoration::Button>();)

namespace OrielOSDecoration {

namespace {
// The space before the app's icon, and between the icon and the title.
constexpr qreal IconMargin = 12;
constexpr qreal IconSize = 16;
constexpr qreal IconSpacing = 8;
// How far outside the window the pointer can still grab an edge to resize it.
constexpr qreal ResizeMargin = 8;
// How much of the window's colour a Mica title bar keeps over the blurred wallpaper.
constexpr qreal MicaOpacity = 0.8;
} // namespace

Decoration::Decoration(QObject *parent, const QVariantList &args)
    : KDecoration3::Decoration(parent, args)
{
}

bool Decoration::init()
{
    const auto w = window();
    const auto s = settings();

    connect(w, &KDecoration3::DecoratedWindow::activeChanged, this, [this]() {
        updateBorders();
        updateShadow();
        updateBlur();
        update();
    });
    connect(w, &KDecoration3::DecoratedWindow::captionChanged, this, [this]() { update(titleBar()); });
    connect(w, &KDecoration3::DecoratedWindow::iconChanged, this, [this]() { update(titleBar()); });
    connect(w, &KDecoration3::DecoratedWindow::paletteChanged, this, [this]() {
        updateBorders();
        update();
    });
    const auto relayout = [this]() {
        updateBorders();
        updateTitleBar();
        updateButtons();
        updateBlur();
    };
    connect(w, &KDecoration3::DecoratedWindow::maximizedChanged, this, relayout);
    connect(w, &KDecoration3::DecoratedWindow::adjacentScreenEdgesChanged, this, relayout);
    connect(w, &KDecoration3::DecoratedWindow::widthChanged, this, [this]() {
        updateTitleBar();
        updateButtons();
        updateBlur();
    });
    connect(w, &KDecoration3::DecoratedWindow::nextScaleChanged, this, [this]() {
        updateBorders();
        updateShadow();
    });
    connect(s.get(), &KDecoration3::DecorationSettings::reconfigured, this, [this]() {
        readTransparency();
        updateBorders();
        updateButtons();
        updateBlur();
        update();
    });
    connect(s.get(), &KDecoration3::DecorationSettings::alphaChannelSupportedChanged, this, [this]() {
        updateBorders();
        updateBlur();
        update();
    });
    connect(s.get(), &KDecoration3::DecorationSettings::decorationButtonsLeftChanged, this, &Decoration::updateButtons);
    connect(s.get(), &KDecoration3::DecorationSettings::decorationButtonsRightChanged, this, &Decoration::updateButtons);

    m_leftButtons = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Left, this, &Button::create);
    m_rightButtons = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Right, this, &Button::create);

    readTransparency();
    updateBorders();
    updateTitleBar();
    updateButtons();
    updateShadow();
    updateBlur();
    return true;
}

bool Decoration::isMaximized() const
{
    return window()->isMaximized();
}

bool Decoration::isMica() const
{
    return m_transparency && window()->isActive() && settings()->isAlphaChannelSupported();
}

void Decoration::readTransparency()
{
    // OrielOS turns the blur on in /etc/xdg/kwinrc; Settings writes the user's choice over it.
    const KSharedConfigPtr kwin = KSharedConfig::openConfig(QStringLiteral("kwinrc"), KConfig::NoGlobals);
    kwin->reparseConfiguration();
    m_transparency = KConfigGroup(kwin, QStringLiteral("Plugins")).readEntry("blurEnabled", true);
}

QColor Decoration::titleBarColor() const
{
    QColor color = window()->palette().color(window()->isActive() ? QPalette::Active : QPalette::Inactive, QPalette::Window);
    if (isMica()) {
        color.setAlphaF(MicaOpacity);
    }
    return color;
}

QPainterPath Decoration::titleBarShape() const
{
    const QRectF bar(0, 0, size().width(), borderTop());
    QPainterPath shape;
    if (isMaximized() || !settings()->isAlphaChannelSupported()) {
        shape.addRect(bar);
        return shape;
    }
    const qreal r = CornerRadius;
    shape.moveTo(bar.left(), bar.bottom());
    shape.lineTo(bar.left(), bar.top() + r);
    shape.arcTo(QRectF(bar.left(), bar.top(), 2 * r, 2 * r), 180, -90);
    shape.lineTo(bar.right() - r, bar.top());
    shape.arcTo(QRectF(bar.right() - 2 * r, bar.top(), 2 * r, 2 * r), 90, -90);
    shape.lineTo(bar.right(), bar.bottom());
    shape.closeSubpath();
    return shape;
}

void Decoration::updateBlur()
{
    // KWin blurs what's behind the title bar, inside its rounded corners, only while it's Mica.
    setBlurRegion(isMica() ? QRegion(titleBarShape().toFillPolygon().toPolygon()) : QRegion());
}

QColor Decoration::foregroundColor() const
{
    QColor color = window()->palette().color(QPalette::Active, QPalette::WindowText);
    if (!window()->isActive()) {
        color.setAlphaF(0.55);
    }
    return color;
}

void Decoration::updateBorders()
{
    const qreal scale = window()->nextScale();
    const bool maximized = isMaximized();
    setBorders(QMarginsF(0, KDecoration3::snapToPixelGrid(TitleBarHeight, scale), 0, 0));
    setResizeOnlyBorders(maximized ? QMarginsF() : QMarginsF(ResizeMargin, 0, ResizeMargin, ResizeMargin));
    setOpaque(maximized && !isMica());

    if (maximized) {
        setBorderRadius(KDecoration3::BorderRadius());
        setBorderOutline(KDecoration3::BorderOutline());
        return;
    }
    // The title bar draws its own top corners; KWin rounds the bottom of the window to match.
    const qreal radius = KDecoration3::snapToPixelGrid(CornerRadius, scale);
    setBorderRadius(KDecoration3::BorderRadius(0, 0, radius, radius));
    // KWin draws the outline opaque, so it's the text colour mixed into the window's.
    const QColor text = window()->palette().color(QPalette::Active, QPalette::WindowText);
    const QColor base = window()->palette().color(QPalette::Active, QPalette::Window);
    const qreal mix = window()->isActive() ? 0.18 : 0.12;
    const QColor outline = QColor::fromRgbF(base.redF() + (text.redF() - base.redF()) * mix, base.greenF() + (text.greenF() - base.greenF()) * mix,
        base.blueF() + (text.blueF() - base.blueF()) * mix);
    const qreal thickness = std::max(KDecoration3::pixelSize(scale), KDecoration3::snapToPixelGrid(1, scale));
    setBorderOutline(KDecoration3::BorderOutline(thickness, outline, KDecoration3::BorderRadius(radius)));
}

void Decoration::updateTitleBar()
{
    setTitleBar(QRectF(0, 0, window()->width(), borderTop()));
}

void Decoration::updateButtons()
{
    const qreal height = borderTop();
    for (auto *button : m_leftButtons->buttons() + m_rightButtons->buttons()) {
        const qreal width = button->type() == KDecoration3::DecorationButtonType::Menu ? height : ButtonWidth;
        button->setGeometry(QRectF(0, 0, width, height));
    }
    m_leftButtons->setSpacing(0);
    m_rightButtons->setSpacing(0);
    m_leftButtons->setPos(QPointF(0, 0));
    m_rightButtons->setPos(QPointF(size().width() - m_rightButtons->geometry().width(), 0));
    update();
}

void Decoration::updateShadow()
{
    setShadow(Shadow::forWindow(window()->isActive(), CornerRadius));
}

void Decoration::paint(QPainter *painter, const QRectF &repaintRegion)
{
    const QRectF bar(0, 0, size().width(), borderTop());
    if (!bar.intersects(repaintRegion)) {
        return;
    }

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);

    // The bar, with rounded top corners unless the window fills the screen. Everything after it,
    // including Close's red, stays inside the same shape.
    const QPainterPath shape = titleBarShape();
    painter->setPen(Qt::NoPen);
    painter->setBrush(titleBarColor());
    painter->drawPath(shape);
    painter->setClipPath(shape);

    // The app's icon and title, unless a window menu button on the left shows the icon.
    qreal x = IconMargin;
    if (!m_leftButtons->buttons().isEmpty()) {
        x = m_leftButtons->geometry().right() + IconSpacing / 2;
    } else {
        const QRectF iconRect(x, (bar.height() - IconSize) / 2, IconSize, IconSize);
        window()->icon().paint(painter, iconRect.toRect(), Qt::AlignCenter, window()->isActive() ? QIcon::Normal : QIcon::Disabled);
        x = iconRect.right() + IconSpacing;
    }
    const qreal right = m_rightButtons->buttons().isEmpty() ? bar.right() - IconMargin : m_rightButtons->geometry().left() - IconSpacing;
    if (right > x) {
        QFont font = settings()->font();
        painter->setFont(font);
        painter->setPen(foregroundColor());
        const QRectF textRect(x, 0, right - x, bar.height());
        const QString caption = painter->fontMetrics().elidedText(window()->caption(), Qt::ElideRight, textRect.width());
        painter->drawText(textRect, Qt::AlignVCenter | Qt::AlignLeft | Qt::TextSingleLine, caption);
    }

    m_leftButtons->paint(painter, repaintRegion);
    m_rightButtons->paint(painter, repaintRegion);
    painter->restore();
}

} // namespace OrielOSDecoration

#include "decoration.moc"
