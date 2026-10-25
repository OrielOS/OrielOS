// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

import { NOT_RUNNING_NOTICE, isEnabled, readConfig } from "./config.js";
import { createRest, describeError, findGuild, listChannels, resolveByName } from "./discord-api.js";
import { messagesFor, sendPosts } from "./posts.js";

async function run(env) {
  const config = readConfig(env);
  if (!isEnabled(config)) {
    console.log(NOT_RUNNING_NOTICE);
    return;
  }

  const eventName = env.GITHUB_EVENT_NAME ?? "";
  const payload = JSON.parse(await readFile(env.GITHUB_EVENT_PATH, "utf8"));
  const messages = messagesFor(eventName, payload, config.repo);
  if (messages.length === 0) {
    console.log("Nothing to post for this event.");
    return;
  }

  const rest = createRest(config.token);
  const guild = await findGuild(rest, config.guildId);
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
