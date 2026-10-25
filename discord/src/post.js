// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

import { NOT_RUNNING_NOTICE, isEnabled, readConfig } from "./config.js";
import {
  createRest,
  describeError,
  findGuild,
  listChannels,
  listRoles,
  resolveByName,
} from "./discord-api.js";
import { fetchCommitCountByAuthor } from "./github.js";
import {
  firstContributionCandidates,
  messagesFor,
  sendPosts,
  welcomeMessage,
  withTestersPing,
} from "./posts.js";

// A welcome for each person whose first commit on main is in this push.
async function welcomes(eventName, payload, config) {
  if (eventName !== "push") return [];
  const result = [];
  try {
    for (const candidate of firstContributionCandidates(payload)) {
      const count = await fetchCommitCountByAuthor(config.repo, candidate.username, config.githubToken);
      if (count === 1) result.push(welcomeMessage(candidate, config.repo));
    }
  } catch (error) {
    console.error(`Could not check for first contributions: ${describeError(error)}.`);
    return [];
  }
  return result;
}

async function testersRoleId(rest, guild, config) {
  try {
    return resolveByName(await listRoles(rest, guild), config.names.testers, "role", {
      ignoreCase: true,
    }).id;
  } catch {
    console.log("There is no Testers role, so the test build is posted without a ping.");
    return null;
  }
}

async function run(env) {
  const config = readConfig(env);
  if (!isEnabled(config)) {
    console.log(NOT_RUNNING_NOTICE);
    return;
  }

  const eventName = env.GITHUB_EVENT_NAME ?? "";
  const payload = JSON.parse(await readFile(env.GITHUB_EVENT_PATH, "utf8"));
  let messages = [
    ...messagesFor(eventName, payload, config.repo),
    ...(await welcomes(eventName, payload, config)),
  ];
  if (messages.length === 0) {
    console.log("Nothing to post for this event.");
    return;
  }

  const rest = createRest(config.token);
  const guild = await findGuild(rest, config.guildId);
  if (messages.some((message) => message.pingTesters)) {
    messages = withTestersPing(messages, await testersRoleId(rest, guild, config));
  }
  const feed = resolveByName(await listChannels(rest, guild), config.names.feed, "channel");
  await sendPosts(rest, feed, messages);
  console.log(`Posted ${messages.length} ${messages.length === 1 ? "message" : "messages"}.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  run(process.env).catch((error) => {
    console.error(`Posting to Discord failed: ${describeError(error)}.`);
    process.exit(1);
  });
}
