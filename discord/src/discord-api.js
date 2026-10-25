// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import { REST, Routes } from "discord.js";

export const EMOJI = "🔗";

const NO_MENTIONS = { parse: [] };

export function withNoMentions(body) {
  return { ...body, allowed_mentions: NO_MENTIONS };
}

export function errorCode(error) {
  return typeof error?.code === "number" ? error.code : null;
}

// Error text can name members, so only codes are ever logged.
export function describeError(error) {
  const code = errorCode(error);
  if (code !== null) return `Discord error code ${code}`;
  if (typeof error?.status === "number") return `Discord status ${error.status}`;
  return typeof error?.message === "string" ? error.message : "an unexpected error";
}

export function resolveByName(items, name, kind, { ignoreCase = false } = {}) {
  const same = (value) =>
    ignoreCase ? value.toLowerCase() === name.toLowerCase() : value === name;
  const matches = items.filter((item) => typeof item.name === "string" && same(item.name));
  if (matches.length === 0) throw new Error(`The ${kind} "${name}" does not exist.`);
  if (matches.length > 1) throw new Error(`More than one ${kind} is called "${name}".`);
  return matches[0];
}

export function createRest(token) {
  return new REST({ version: "10" }).setToken(token);
}

export async function findGuild(rest, guildId) {
  if (guildId) return guildId;
  const guilds = await rest.get(Routes.userGuilds());
  if (guilds.length !== 1) {
    throw new Error(
      `The bot is in ${guilds.length} servers. Set DISCORD_GUILD_ID, or put the bot in exactly one.`,
    );
  }
  return guilds[0].id;
}

export async function botUserId(rest) {
  return (await rest.get(Routes.user())).id;
}

export const listChannels = (rest, guild) => rest.get(Routes.guildChannels(guild));
export const listRoles = (rest, guild) => rest.get(Routes.guildRoles(guild));

export function fetchMessages(rest, channel, before) {
  const query = new URLSearchParams({ limit: "100" });
  if (before) query.set("before", before);
  return rest.get(Routes.channelMessages(channel), { query });
}

export const getMessage = (rest, channel, message) =>
  rest.get(Routes.channelMessage(channel, message));

export const sendMessage = (rest, channel, body) =>
  rest.post(Routes.channelMessages(channel), { body: withNoMentions(body) });

export const editMessage = (rest, channel, message, body) =>
  rest.patch(Routes.channelMessage(channel, message), { body: withNoMentions(body) });

export const deleteMessage = (rest, channel, message) =>
  rest.delete(Routes.channelMessage(channel, message));

export const crosspost = (rest, channel, message) =>
  rest.post(Routes.channelMessageCrosspost(channel, message));

export const addOwnReaction = (rest, channel, message) =>
  rest.put(Routes.channelMessageOwnReaction(channel, message, encodeURIComponent(EMOJI)));

export const removeUserReaction = (rest, channel, message, user) =>
  rest.delete(
    Routes.channelMessageUserReaction(channel, message, encodeURIComponent(EMOJI), user),
  );

export async function listReactors(rest, channel, message) {
  const users = [];
  let after;
  for (;;) {
    const query = new URLSearchParams({ limit: "100" });
    if (after) query.set("after", after);
    const page = await rest.get(
      Routes.channelMessageReaction(channel, message, encodeURIComponent(EMOJI)),
      { query },
    );
    users.push(...page);
    if (page.length < 100) return users;
    after = page[page.length - 1].id;
  }
}

export async function sendDirectMessage(rest, user, content) {
  const dm = await rest.post(Routes.userChannels(), { body: { recipient_id: user } });
  return sendMessage(rest, dm.id, { content });
}

export const getMember = (rest, guild, user) => rest.get(Routes.guildMember(guild, user));

export const addRole = (rest, guild, user, role, reason) =>
  rest.put(Routes.guildMemberRole(guild, user, role), { reason });

export const removeRole = (rest, guild, user, role, reason) =>
  rest.delete(Routes.guildMemberRole(guild, user, role), { reason });
