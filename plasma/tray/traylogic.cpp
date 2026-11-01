// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "traylogic.h"

#include <algorithm>

namespace Tray {

Split split(const QStringList &present, const QStringList &passive, const QStringList &shown)
{
    Split result;
    for (const QString &id : shown) {
        if (present.contains(id) && !passive.contains(id) && !result.taskbar.contains(id)) {
            result.taskbar.append(id);
        }
    }
    for (const QString &id : present) {
        if (!result.taskbar.contains(id) && !result.pane.contains(id)) {
            result.pane.append(id);
        }
    }
    return result;
}

QStringList showAt(const QStringList &shown, const QString &id, int index)
{
    QStringList result = hide(shown, id);
    result.insert(std::clamp(index, 0, int(result.size())), id);
    return result;
}

QStringList hide(const QStringList &shown, const QString &id)
{
    QStringList result = shown;
    result.removeAll(id);
    return result;
}

QString driveName(const QString &label, const QString &vendor, const QString &product, const QString &description)
{
    if (!label.trimmed().isEmpty()) {
        return label.trimmed();
    }
    const QString model = QStringList { vendor.trimmed(), product.trimmed() }.join(QLatin1Char(' ')).trimmed();
    return model.isEmpty() ? description.trimmed() : model;
}

} // namespace Tray
