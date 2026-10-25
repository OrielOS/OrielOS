// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { NOT_RUNNING_NOTICE, isEnabled, readConfig } from "./config.js";
import {
  EMOJI,
  addOwnReaction,
  addRole,
  botUserId,
  createRest,
  describeError,
  errorCode,
  findGuild,
  getMember,
  getMessage,
  listChannels,
  listReactors,
  listRoles,
  removeRole,
  removeUserReaction,
  resolveByName,
  sendDirectMessage,
  sendMessage,
} from "./discord-api.js";
import {
  fetchContributorIds,
  fetchGithubUser,
  readMaintainers,
  requestDeviceCode,
  waitForToken,
} from "./github.js";
import { desiredRoles, roleChanges } from "./roles.js";
import {
  deleteRecord,
  linksToMove,
  linksToUnlink,
  loadStore,
  planLink,
  saveRecord,
  updateRecord,
} from "./store.js";

const MAX_NEW_LINKS = 10;
const REASON = "Synced from GitHub";
const UNKNOWN_MEMBER = 10007;
const UNKNOWN_MESSAGE = 10008;
const CANNOT_DM = 50007;

const here = path.dirname(fileURLToPath(import.meta.url));
const CODEOWNERS = path.resolve(here, "../../.github/CODEOWNERS");

export const WELCOME_TEXT =
  "**Link your GitHub account** to get the Maintainer or Contributor role. " +
  `React with ${EMOJI} below, and within about ten minutes the OrielOS bot will send you a code to enter on GitHub. ` +
  "Allow direct messages from server members first. Remove your reaction to unlink. " +
  "The bot stores only your Discord and GitHub account IDs.";

export function codeMessage(userCode) {
  return (
    "To link your GitHub account to the OrielOS Discord server, open https://github.com/login/device " +
    `and enter **${userCode}**. The code works for 15 minutes. ` +
    `If you didn't react ${EMOJI} in the OrielOS server, ignore this message.`
  );
}

async function setup(config, rest) {
  const guild = await findGuild(rest, config.guildId);
  const channels = await listChannels(rest, guild);
  const roles = await listRoles(rest, guild);
  const names = config.names;
  const roleFor = (name) => resolveByName(roles, name, "role", { ignoreCase: true });
  return {
    guild,
    channels: {
      welcome: resolveByName(channels, names.welcome, "channel").id,
      state: resolveByName(channels, names.state, "channel").id,
      log: resolveByName(channels, names.log, "channel").id,
    },
    roleIds: {
      maintainer: roleFor(names.maintainer).id,
      contributor: roleFor(names.contributor).id,
    },
    roleNames: { maintainer: names.maintainer, contributor: names.contributor },
  };
}

async function ensureWelcome(ctx) {
  const { rest, channels, store } = ctx;
  if (store.welcome) {
    try {
      await getMessage(rest, channels.welcome, store.welcome.message);
      return store.welcome.message;
    } catch (error) {
      if (errorCode(error) !== UNKNOWN_MESSAGE) throw error;
      await deleteRecord(rest, channels.state, store.welcome);
    }
  }
  const message = await sendMessage(rest, channels.welcome, { content: WELCOME_TEXT });
  await addOwnReaction(rest, channels.welcome, message.id);
  store.welcome = await saveRecord(rest, channels.state, { kind: "welcome", message: message.id });
  return message.id;
}

async function modLog(ctx, content) {
  try {
    await sendMessage(ctx.rest, ctx.channels.log, { content });
  } catch (error) {
    console.error(`Could not write to the moderation log: ${describeError(error)}.`);
  }
}

async function memberRoles(ctx, user) {
  const member = await getMember(ctx.rest, ctx.guild, user);
  return member.roles;
}

async function applyChanges(ctx, link, current, desired) {
  const { rest, guild, roleIds, roleNames } = ctx;
  const changes = roleChanges(current, desired, roleIds);
  for (const key of changes.add) {
    await addRole(rest, guild, link.discord, roleIds[key], REASON);
    ctx.stats.changes += 1;
    await modLog(ctx, `Gave <@${link.discord}> the ${roleNames[key]} role (GitHub: ${link.login})`);
  }
  for (const key of changes.remove) {
    await removeRole(rest, guild, link.discord, roleIds[key], REASON);
    ctx.stats.changes += 1;
    await modLog(
      ctx,
      `Removed the ${roleNames[key]} role from <@${link.discord}> (GitHub: ${link.login})`,
    );
  }
  return changes;
}

async function syncMember(ctx, link) {
  const current = await memberRoles(ctx, link.discord);
  return applyChanges(ctx, link, current, desiredRoles(link, ctx.who));
}

async function removeSyncedRoles(ctx, link) {
  try {
    const current = await memberRoles(ctx, link.discord);
    await applyChanges(ctx, link, current, { maintainer: false, contributor: false });
  } catch (error) {
    if (errorCode(error) === UNKNOWN_MEMBER) return;
    ctx.stats.errors += 1;
    console.error(`Could not remove a member's roles: ${describeError(error)}.`);
  }
}

async function dropLink(ctx, link) {
  await deleteRecord(ctx.rest, ctx.channels.state, link);
  ctx.store.links = ctx.store.links.filter((item) => item.id !== link.id);
}

async function moveToCurrentWelcome(ctx, reactorIds) {
  for (const link of linksToMove(ctx.store.links, reactorIds, ctx.welcomeMessage)) {
    try {
      await updateRecord(ctx.rest, ctx.channels.state, Object.assign(link, { on: ctx.welcomeMessage }));
    } catch (error) {
      ctx.stats.errors += 1;
      console.error(`Could not update a link: ${describeError(error)}.`);
    }
  }
}

async function unlinkMissing(ctx, reactorIds) {
  for (const link of linksToUnlink(ctx.store.links, reactorIds, ctx.welcomeMessage)) {
    try {
      await removeSyncedRoles(ctx, link);
      await dropLink(ctx, link);
      ctx.stats.unlinked += 1;
      await modLog(ctx, `<@${link.discord}> unlinked GitHub account ${link.login}`);
    } catch (error) {
      ctx.stats.errors += 1;
      console.error(`Could not unlink a member: ${describeError(error)}.`);
    }
  }
}

async function syncAll(ctx) {
  for (const link of [...ctx.store.links]) {
    try {
      await syncMember(ctx, link);
    } catch (error) {
      if (errorCode(error) === UNKNOWN_MEMBER) {
        await dropLink(ctx, link);
        ctx.stats.unlinked += 1;
        await modLog(ctx, `<@${link.discord}> left the server, so GitHub account ${link.login} was unlinked`);
        continue;
      }
      ctx.stats.errors += 1;
      console.error(`Could not sync a member: ${describeError(error)}.`);
    }
  }
}

async function tryDm(ctx, user, content) {
  try {
    await sendDirectMessage(ctx.rest, user, content);
    return true;
  } catch (error) {
    if (errorCode(error) !== CANNOT_DM) {
      console.error(`Could not send a direct message: ${describeError(error)}.`);
    }
    return false;
  }
}

const unreact = (ctx, user) =>
  removeUserReaction(ctx.rest, ctx.channels.welcome, ctx.welcomeMessage, user).catch(() => {});

async function linkMember(ctx, reactor) {
  const { config } = ctx;
  const flow = await requestDeviceCode(config.linkClientId);
  if (!(await tryDm(ctx, reactor.id, codeMessage(flow.userCode)))) {
    await unreact(ctx, reactor.id);
    return;
  }

  const token = await waitForToken(config.linkClientId, flow);
  if (token === null) {
    await unreact(ctx, reactor.id);
    await tryDm(
      ctx,
      reactor.id,
      "The code expired, so your GitHub account wasn't linked. React 🔗 in #welcome to try again.",
    );
    return;
  }

  const { id, login } = await fetchGithubUser(token);
  const plan = planLink(ctx.store.links, { discord: reactor.id, github: id });
  for (const old of plan.moved) {
    await removeSyncedRoles(ctx, old);
    await modLog(ctx, `GitHub account ${old.login} moved from <@${old.discord}> to <@${reactor.id}>`);
  }
  for (const old of plan.remove) await dropLink(ctx, old);
  const link = await saveRecord(ctx.rest, ctx.channels.state, {
    kind: "link",
    discord: reactor.id,
    github: id,
    login,
    at: new Date().toISOString(),
    on: ctx.welcomeMessage,
  });
  ctx.store.links.push(link);
  ctx.stats.linked += 1;

  const changes = await syncMember(ctx, link);
  const names = changes.add.map((key) => ctx.roleNames[key]);
  await tryDm(
    ctx,
    reactor.id,
    `Linked to GitHub account ${login}.` +
      (names.length > 0 ? ` You now have the ${names.join(" and ")} ${names.length > 1 ? "roles" : "role"}.` : ""),
  );
  await modLog(ctx, `<@${reactor.id}> linked GitHub account ${login}`);
}

async function linkNewMembers(ctx, reactors) {
  const linked = new Set(ctx.store.links.map((link) => link.discord));
  const pending = reactors.filter((user) => !linked.has(user.id)).slice(0, MAX_NEW_LINKS);
  await Promise.all(
    pending.map((reactor) =>
      linkMember(ctx, reactor).catch((error) => {
        ctx.stats.errors += 1;
        console.error(`Could not link a member: ${describeError(error)}.`);
      }),
    ),
  );
}

async function run(env) {
  const config = readConfig(env);
  if (!isEnabled(config)) {
    console.log(NOT_RUNNING_NOTICE);
    return 0;
  }

  const rest = createRest(config.token);
  const found = await setup(config, rest);
  const store = await loadStore(rest, found.channels.state, await botUserId(rest));
  const ctx = {
    ...found,
    rest,
    config,
    store,
    who: { maintainers: [], contributorIds: [] },
    stats: { linked: 0, unlinked: 0, changes: 0, errors: 0 },
  };

  ctx.welcomeMessage = await ensureWelcome(ctx);
  const reactors = (await listReactors(rest, found.channels.welcome, ctx.welcomeMessage)).filter(
    (user) => !user.bot,
  );
  const reactorIds = new Set(reactors.map((user) => user.id));
  await moveToCurrentWelcome(ctx, reactorIds);
  await unlinkMissing(ctx, reactorIds);

  ctx.who = {
    maintainers: await readMaintainers(CODEOWNERS),
    contributorIds: await fetchContributorIds(config.repo, config.githubToken),
  };
  await syncAll(ctx);

  if (config.linkClientId) await linkNewMembers(ctx, reactors);
  else console.log("LINK_CLIENT_ID is not set, so new members are not being linked.");

  const { linked, unlinked, changes, errors } = ctx.stats;
  console.log(
    `Linked ${linked} ${linked === 1 ? "account" : "accounts"}. Unlinked ${unlinked}. Role changes: ${changes}.` +
      (errors > 0 ? ` Errors: ${errors}.` : ""),
  );
  return errors > 0 ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  run(process.env).then(
    (code) => process.exit(code),
    (error) => {
      console.error(`The Discord sync failed: ${describeError(error)}.`);
      process.exit(1);
    },
  );
}
