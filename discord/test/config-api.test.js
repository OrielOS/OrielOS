// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import test from "node:test";

import { NOT_RUNNING_NOTICE, isEnabled, readConfig } from "../src/config.js";
import {
  describeError,
  errorCode,
  resolveByName,
  sendMessage,
  withNoMentions,
} from "../src/discord-api.js";
import { messagesFor, sendPosts } from "../src/posts.js";

test("an empty token means the bot does not run", () => {
  assert.equal(isEnabled(readConfig({})), false);
  assert.equal(isEnabled(readConfig({ DISCORD_TOKEN: "  " })), false);
  assert.equal(isEnabled(readConfig({ DISCORD_TOKEN: "t" })), true);
  assert.equal(
    NOT_RUNNING_NOTICE,
    "::notice::DISCORD_TOKEN is not set, so the Discord bot is not running.",
  );
});

test("configuration has defaults", () => {
  const config = readConfig({});
  assert.equal(config.repo, "ncjsvr/OrielOS");
  assert.equal(config.linkClientId, "");
  assert.equal(config.guildId, "");
  assert.equal(config.linkMessage, "");
  assert.deepEqual(config.names, {
    link: "about",
    state: "bot-state",
    log: "mod-log",
    feed: "github-feed",
    maintainer: "Maintainer",
    contributor: "Contributor",
    testers: "Testers",
  });
});

test("configuration reads overrides", () => {
  const config = readConfig({
    GITHUB_REPOSITORY: "a/b",
    CHANNEL_FEED: "news",
    ROLE_CONTRIBUTOR: "Helper",
    LINK_CLIENT_ID: "abc",
  });
  assert.equal(config.repo, "a/b");
  assert.equal(config.names.feed, "news");
  assert.equal(config.names.contributor, "Helper");
  assert.equal(config.linkClientId, "abc");
});

test("resolveByName needs exactly one match", () => {
  const items = [{ id: "1", name: "welcome" }, { id: "2", name: "Maintainer" }, { id: "3", name: "maintainer" }];
  assert.equal(resolveByName(items, "welcome", "channel").id, "1");
  assert.throws(() => resolveByName(items, "Welcome", "channel"), /channel "Welcome" does not exist/);
  assert.throws(
    () => resolveByName(items, "MAINTAINER", "role", { ignoreCase: true }),
    /More than one role/,
  );
  assert.equal(resolveByName(items, "WELCOME", "role", { ignoreCase: true }).id, "1");
});

test("resolveByName also finds an item by its ID", () => {
  const items = [{ id: "1563925111805845534", name: "about" }, { id: "1563925191057346662", name: "github-feed" }];
  assert.equal(resolveByName(items, "1563925191057346662", "channel").name, "github-feed");
  assert.throws(() => resolveByName(items, "1563925111805845535", "channel"), /does not exist/);
});

test("error helpers expose codes only", () => {
  assert.equal(errorCode({ code: 10007 }), 10007);
  assert.equal(errorCode({ code: "ECONNRESET" }), null);
  assert.equal(describeError({ code: 50007, message: "Cannot send messages to this user" }), "Discord error code 50007");
});

test("withNoMentions forbids every mention", () => {
  assert.deepEqual(withNoMentions({ content: "<@1> @everyone" }), {
    content: "<@1> @everyone",
    allowed_mentions: { parse: [] },
  });
});

function fakeRest() {
  const calls = [];
  return {
    calls,
    post: async (route, options) => {
      calls.push({ route, options });
      return { id: String(calls.length) };
    },
  };
}

test("sendMessage adds allowed_mentions to every message", async () => {
  const rest = fakeRest();
  await sendMessage(rest, "10", { content: "hello <@1>" });
  assert.deepEqual(rest.calls[0].options.body.allowed_mentions, { parse: [] });
});

test("sendPosts sends each post with no mentions and does not crosspost merges", async () => {
  const rest = fakeRest();
  const payload = {
    ref: "refs/heads/main",
    commits: [{ message: "Fix a thing (#4)", author: { name: "Alice", username: "alice" } }],
  };
  const messages = messagesFor("push", payload, "ncjsvr/OrielOS");
  await sendPosts(rest, { id: "10", type: 5 }, messages);
  assert.equal(rest.calls.length, 1);
  assert.deepEqual(rest.calls[0].options.body.allowed_mentions, { parse: [] });
  assert.equal("crosspost" in rest.calls[0].options.body, false);
});

test("sendPosts crossposts releases to an announcement channel", async () => {
  const rest = fakeRest();
  const release = { name: "1.0", draft: false, prerelease: false };
  await sendPosts(rest, { id: "10", type: 5 }, messagesFor("release", { action: "published", release }, "a/b"));
  assert.equal(rest.calls.length, 2);
  assert.match(rest.calls[1].route, /crosspost$/);
  assert.equal("crosspost" in rest.calls[0].options.body, false);
});

test("sendPosts pings everyone for a full release only", async () => {
  const release = {
    name: "1.0",
    html_url: "https://github.com/ncjsvr/OrielOS/releases/tag/v1.0",
    draft: false,
    prerelease: false,
  };
  const rest = fakeRest();
  await sendPosts(rest, { id: "10", type: 0 }, messagesFor("release", { action: "published", release }, "a/b"));
  assert.equal(rest.calls[0].options.body.content, "@everyone");
  assert.deepEqual(rest.calls[0].options.body.allowed_mentions, { parse: ["everyone"] });
  assert.equal("mentions" in rest.calls[0].options.body, false);

  const beta = fakeRest();
  const prerelease = { ...release, prerelease: true };
  await sendPosts(beta, { id: "10", type: 0 }, messagesFor("release", { action: "published", release: prerelease }, "a/b"));
  assert.equal(beta.calls[0].options.body.content, undefined);
  assert.deepEqual(beta.calls[0].options.body.allowed_mentions, { parse: [] });
});

test("sendPosts ignores crosspost failures", async () => {
  const rest = {
    post: async (route) => {
      if (route.endsWith("crosspost")) throw new Error("no");
      return { id: "1" };
    },
  };
  await sendPosts(rest, { id: "10", type: 5 }, [{ embeds: [], crosspost: true }]);
});
