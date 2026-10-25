// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import { deleteMessage, editMessage, fetchMessages, sendMessage } from "./discord-api.js";

const MAX_PAGES = 50;

export function parseRecord(content) {
  let value;
  try {
    value = JSON.parse(content);
  } catch {
    return null;
  }
  if (value === null || typeof value !== "object") return null;
  if (
    value.kind === "link" &&
    typeof value.discord === "string" &&
    Number.isInteger(value.github) &&
    typeof value.login === "string" &&
    typeof value.at === "string"
  ) {
    const { kind, discord, github, login, at } = value;
    const record = { kind, discord, github, login, at };
    if (typeof value.on === "string") record.on = value.on;
    return record;
  }
  if (value.kind === "welcome" && typeof value.message === "string") {
    return { kind: "welcome", message: value.message };
  }
  return null;
}

export function serialiseRecord(record) {
  if (record.kind === "link") {
    const { kind, discord, github, login, at, on } = record;
    return JSON.stringify({ kind, discord, github, login, at, on });
  }
  return JSON.stringify({ kind: "welcome", message: record.message });
}

// Links are given newest first. Keeps the first link for each Discord and GitHub ID.
export function dedupeLinks(links) {
  const keep = [];
  const drop = [];
  const discords = new Set();
  const githubs = new Set();
  for (const link of links) {
    if (discords.has(link.discord) || githubs.has(link.github)) {
      drop.push(link);
    } else {
      discords.add(link.discord);
      githubs.add(link.github);
      keep.push(link);
    }
  }
  return { keep, drop };
}

// Which stored links a new link replaces, and which of those belong to other members.
export function planLink(links, { discord, github }) {
  const remove = links.filter((link) => link.discord === discord || link.github === github);
  const moved = remove.filter((link) => link.discord !== discord);
  return { remove, moved };
}

// A link remembers the welcome message it was made on (`on`). Only removing the
// reaction from that same message unlinks, so a reposted welcome message
// doesn't unlink everyone.
export function linksToUnlink(links, reactorIds, welcomeId) {
  return links.filter(
    (link) => !reactorIds.has(link.discord) && (link.on === undefined || link.on === welcomeId),
  );
}

// Links made on an older welcome message whose member has reacted on the current one.
export function linksToMove(links, reactorIds, welcomeId) {
  return links.filter(
    (link) => reactorIds.has(link.discord) && link.on !== undefined && link.on !== welcomeId,
  );
}

export async function loadStore(rest, channel, botId) {
  const entries = [];
  let before;
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const messages = await fetchMessages(rest, channel, before);
    for (const message of messages) {
      if (message.author?.id !== botId) continue;
      const record = parseRecord(message.content);
      if (record) entries.push({ ...record, id: message.id });
    }
    if (messages.length < 100) break;
    before = messages[messages.length - 1].id;
  }

  const { keep, drop } = dedupeLinks(entries.filter((entry) => entry.kind === "link"));
  const welcomes = entries.filter((entry) => entry.kind === "welcome");
  for (const entry of [...drop, ...welcomes.slice(1)]) {
    await deleteMessage(rest, channel, entry.id);
  }
  return { links: keep, welcome: welcomes[0] ?? null };
}

export async function saveRecord(rest, channel, record) {
  const message = await sendMessage(rest, channel, { content: serialiseRecord(record) });
  return { ...record, id: message.id };
}

export async function updateRecord(rest, channel, record) {
  await editMessage(rest, channel, record.id, { content: serialiseRecord(record) });
  return record;
}

export const deleteRecord = (rest, channel, record) => deleteMessage(rest, channel, record.id);
