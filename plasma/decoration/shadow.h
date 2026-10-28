// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KDecoration3/DecorationShadow>

#include <memory>

namespace OrielOSDecoration::Shadow {

/**
 * Sill's window shadow: a wide soft shadow a little below the window and a tight one around it,
 * fainter for windows that aren't in use. Made once for each and shared by every window.
 */
std::shared_ptr<KDecoration3::DecorationShadow> forWindow(bool active, qreal cornerRadius);

} // namespace OrielOSDecoration::Shadow
