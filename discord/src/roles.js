// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

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
