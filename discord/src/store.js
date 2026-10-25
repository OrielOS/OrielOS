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
  if (value.kind === "feed" && Number.isInteger(value.pr) && value.pr >= 0) {
    const record = { kind: "feed", pr: value.pr };
    if (Number.isInteger(value.stars) && value.stars >= 0) record.stars = value.stars;
    return record;
  }
  // Older records written before there were several opt-in roles.
  if (value.kind === "tester" && typeof value.discord === "string" && value.discord !== "") {
    return { kind: "optin", role: "testers", discord: value.discord };
  }
  if (
    value.kind === "optin" &&
    typeof value.role === "string" &&
    /^[a-z]+$/.test(value.role) &&
    typeof value.discord === "string" &&
    value.discord !== ""
  ) {
    return { kind: "optin", role: value.role, discord: value.discord };
  }
  return null;
}

export function serialiseRecord(record) {
  if (record.kind === "link") {
    const { kind, discord, github, login, at, on } = record;
    return JSON.stringify({ kind, discord, github, login, at, on });
  }
  if (record.kind === "feed") {
    return JSON.stringify({ kind: "feed", pr: record.pr, stars: record.stars });
  }
  if (record.kind === "optin") {
    return JSON.stringify({ kind: "optin", role: record.role, discord: record.discord });
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

// For one opt-in role and its records: who to give the role (reacted, no record) and whose
// record to drop (reaction gone).
export function planOptIns(reactorIds, records) {
  const known = new Set(records.map((record) => record.discord));
  return {
    add: [...reactorIds].filter((id) => !known.has(id)),
    remove: records.filter((record) => !reactorIds.has(record.discord)),
  };
}

// Records are given newest first. Keeps the first record for each role and member.
export function dedupeOptIns(records) {
  const seen = new Set();
  const keep = [];
  const drop = [];
  for (const record of records) {
    const key = `${record.role}:${record.discord}`;
    if (seen.has(key)) drop.push(record);
    else {
      seen.add(key);
      keep.push(record);
    }
  }
  return { keep, drop };
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
  const feeds = entries.filter((entry) => entry.kind === "feed");
  const optIns = dedupeOptIns(entries.filter((entry) => entry.kind === "optin"));
  for (const entry of [...drop, ...welcomes.slice(1), ...feeds.slice(1), ...optIns.drop]) {
    await deleteMessage(rest, channel, entry.id);
  }
  return {
    links: keep,
    welcome: welcomes[0] ?? null,
    feed: feeds[0] ?? null,
    optIns: optIns.keep,
  };
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
