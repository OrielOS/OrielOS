// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "shadow.h"

#include <QImage>
#include <QPainter>

#include <algorithm>
#include <cmath>
#include <vector>

namespace OrielOSDecoration::Shadow {

namespace {

struct Layer
{
    QPointF offset;
    int blur;
    qreal opacity;
};

// How far the shadow reaches beyond the window, which must hold the widest blur and its offset.
constexpr int Reach = 44;
// How far the shadow runs under the window's edge, so no gap shows at fractional scales.
constexpr int Overlap = 4;

// One pass of a box blur of the given radius over a row or a column of the alpha values.
void boxBlur(std::vector<float> &values, int width, int height, int radius, bool horizontal)
{
    if (radius < 1) {
        return;
    }
    std::vector<float> line(std::max(width, height));
    const int lines = horizontal ? height : width;
    const int length = horizontal ? width : height;
    const float scale = 1.0f / (2 * radius + 1);
    for (int l = 0; l < lines; ++l) {
        auto at = [&](int i) -> float & { return horizontal ? values[l * width + i] : values[i * width + l]; };
        for (int i = 0; i < length; ++i) {
            line[i] = at(i);
        }
        float sum = 0;
        for (int i = -radius; i <= radius; ++i) {
            sum += line[std::clamp(i, 0, length - 1)];
        }
        for (int i = 0; i < length; ++i) {
            at(i) = sum * scale;
            sum += line[std::clamp(i + radius + 1, 0, length - 1)] - line[std::clamp(i - radius, 0, length - 1)];
        }
    }
}

std::shared_ptr<KDecoration3::DecorationShadow> make(const std::vector<Layer> &layers, qreal radius)
{
    // The window's stand-in: just big enough for its rounded corners.
    const int box = static_cast<int>(std::ceil(2 * radius)) + 2;
    const int size = box + 2 * Reach;
    std::vector<float> total(size * size, 0.0f);

    for (const Layer &layer : layers) {
        QImage shape(size, size, QImage::Format_Alpha8);
        shape.fill(0);
        {
            QPainter p(&shape);
            p.setRenderHint(QPainter::Antialiasing);
            p.setPen(Qt::NoPen);
            p.setBrush(Qt::black);
            p.drawRoundedRect(QRectF(QPointF(Reach, Reach) + layer.offset, QSizeF(box, box)), radius, radius);
        }
        std::vector<float> alpha(size * size);
        for (int y = 0; y < size; ++y) {
            const uchar *row = shape.constScanLine(y);
            for (int x = 0; x < size; ++x) {
                alpha[y * size + x] = row[x] / 255.0f;
            }
        }
        // Three box blurs come close to a Gaussian.
        const int pass = std::max(1, layer.blur / 3);
        for (int i = 0; i < 3; ++i) {
            boxBlur(alpha, size, size, pass, true);
            boxBlur(alpha, size, size, pass, false);
        }
        for (int i = 0; i < size * size; ++i) {
            const float a = alpha[i] * static_cast<float>(layer.opacity);
            total[i] = total[i] + a * (1.0f - total[i]);
        }
    }

    QImage image(size, size, QImage::Format_ARGB32_Premultiplied);
    for (int y = 0; y < size; ++y) {
        auto *row = reinterpret_cast<QRgb *>(image.scanLine(y));
        for (int x = 0; x < size; ++x) {
            row[x] = qRgba(0, 0, 0, static_cast<int>(std::round(std::clamp(total[y * size + x], 0.0f, 1.0f) * 255)));
        }
    }
    // Nothing under the window itself, which can be translucent.
    {
        QPainter p(&image);
        p.setRenderHint(QPainter::Antialiasing);
        p.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        p.setPen(Qt::NoPen);
        p.setBrush(Qt::black);
        p.drawRoundedRect(QRectF(Reach + 2, Reach + 2, box - 4, box - 4), radius, radius);
    }

    auto shadow = std::make_shared<KDecoration3::DecorationShadow>();
    const qreal padding = Reach - Overlap;
    shadow->setPadding(QMarginsF(padding, padding, padding, padding));
    shadow->setInnerShadowRect(QRectF(size / 2.0, size / 2.0, 1, 1));
    shadow->setShadow(image);
    return shadow;
}

} // namespace

std::shared_ptr<KDecoration3::DecorationShadow> forWindow(bool active, qreal cornerRadius)
{
    static std::shared_ptr<KDecoration3::DecorationShadow> activeShadow;
    static std::shared_ptr<KDecoration3::DecorationShadow> inactiveShadow;
    auto &shadow = active ? activeShadow : inactiveShadow;
    if (!shadow) {
        const qreal strength = active ? 1.0 : 0.6;
        shadow = make({ { QPointF(0, 8), 32, 0.32 * strength }, { QPointF(0, 1), 6, 0.20 * strength } }, cornerRadius);
    }
    return shadow;
}

} // namespace OrielOSDecoration::Shadow
