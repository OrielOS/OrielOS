// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import { AMD_EMOJI, NVIDIA_EMOJI, TESTER_EMOJI } from "./discord-api.js";

// Roles members give themselves by reacting on the link message. `key` names the role in the
// configuration and in the stored records.
export const OPT_IN_ROLES = [
  {
    key: "testers",
    emoji: TESTER_EMOJI,
    label: "Testers",
    reason: "Asked for test build pings",
    off: "test build pings are off",
  },
  {
    key: "nvidia",
    emoji: NVIDIA_EMOJI,
    label: "NVIDIA",
    reason: "Has an NVIDIA graphics card",
    off: "its reaction is off",
  },
  {
    key: "amd",
    emoji: AMD_EMOJI,
    label: "AMD",
    reason: "Has an AMD graphics card",
    off: "its reaction is off",
  },
];

export function desiredRoles(link, { maintainers, contributorIds }) {
  return {
    maintainer: maintainers.includes(link.login.toLowerCase()),
    contributor: contributorIds.includes(link.github),
  };
}

export function roleChanges(memberRoleIds, desired, roleIds) {
  const add = [];
  const remove = [];
  for (const key of ["maintainer", "contributor"]) {
    const has = memberRoleIds.includes(roleIds[key]);
    if (desired[key] && !has) add.push(key);
    if (!desired[key] && has) remove.push(key);
  }
  return { add, remove };
}
