// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import test from "node:test";

import { clean, formatSize, isoFrom, messagesFor } from "../src/posts.js";

const repo = "ncjsvr/OrielOS";

const release = {
  name: "1.0",
  tag_name: "v1.0",
  html_url: "https://github.com/ncjsvr/OrielOS/releases/tag/v1.0",
  body: "Notes for *everyone*",
  draft: false,
  prerelease: false,
  assets: [
    { name: "notes.txt", size: 10, browser_download_url: "https://github.com/x/notes.txt" },
    {
      name: "OrielOS.iso",
      state: "uploaded",
      size: 2_400_000_000,
      browser_download_url: "https://github.com/ncjsvr/OrielOS/releases/download/v1.0/OrielOS.iso",
    },
  ],
};

test("a published release becomes one embed", () => {
  const [message] = messagesFor("release", { action: "published", release }, repo);
  const [embed] = message.embeds;
  assert.equal(embed.title, "OrielOS 1.0 is out");
  assert.equal(embed.url, release.html_url);
  assert.equal(embed.color, 0x3a66f0);
  assert.equal(embed.description, "Notes for *everyone*");
  assert.deepEqual(embed.fields, [
    {
      name: "Installer",
      value: "[Download the ISO](https://github.com/ncjsvr/OrielOS/releases/download/v1.0/OrielOS.iso) (2.4 GB)",
    },
  ]);
});

test("a pre-release is labelled", () => {
  const [message] = messagesFor(
    "release",
    { action: "published", release: { ...release, prerelease: true, assets: [] } },
    repo,
  );
  assert.equal(message.embeds[0].title, "Pre-release: 1.0");
  assert.equal(message.embeds[0].fields, undefined);
});

test("drafts and other release actions are skipped", () => {
  assert.deepEqual(messagesFor("release", { action: "published", release: { ...release, draft: true } }, repo), []);
  assert.deepEqual(messagesFor("release", { action: "created", release }, repo), []);
});

test("isoFrom and formatSize", () => {
  assert.equal(isoFrom([]), null);
  assert.equal(isoFrom(release.assets).size, "2.4 GB");
  assert.equal(formatSize(5_000_000), "5 MB");
  assert.equal(formatSize(10), "1 MB");
});

test("release notes are cut to 1000 characters", () => {
  const body = "x".repeat(1500);
  const [message] = messagesFor("release", { action: "published", release: { ...release, body } }, repo);
  const description = message.embeds[0].description;
  assert.equal(description.length, 1000);
  assert.ok(description.endsWith("…"));
});

test("clean never ends on a lone backslash", () => {
  assert.equal(clean("_".repeat(10), 4), "\\_…");
  assert.equal(clean("_".repeat(10), 5), "\\_\\_…");
});

const commit = (message, extra = {}) => ({
  message,
  url: `https://github.com/ncjsvr/OrielOS/commit/${message.length}`,
  timestamp: "2026-05-01T10:00:00Z",
  author: { name: "Alice", username: "alice" },
  ...extra,
});

const push = (commits, ref = "refs/heads/main") => ({ ref, commits });

test("a squash merge links to its pull request", () => {
  const [message] = messagesFor(
    "push",
    push([commit("feat: add a thing (#12)\n\nLong body")]),
    repo,
  );
  const [embed] = message.embeds;
  assert.equal(embed.title, "Merged: feat: add a thing (#12)");
  assert.equal(embed.url, "https://github.com/ncjsvr/OrielOS/pull/12");
  assert.deepEqual(embed.footer, { text: "alice" });
  assert.equal(embed.timestamp, "2026-05-01T10:00:00Z");
  assert.equal(embed.color, 0x3a66f0);
});

test("a commit without a pull request number links to the commit", () => {
  const [message] = messagesFor("push", push([commit("Fix the _thing_")]), repo);
  assert.equal(message.embeds[0].title, "Merged: Fix the \\_thing\\_");
  assert.match(message.embeds[0].url, /\/commit\//);
});

test("bot commits are skipped", () => {
  const messages = messagesFor(
    "push",
    push([
      commit("Bump x (#1)", { author: { name: "dependabot[bot]", username: "dependabot[bot]" } }),
      commit("Other", { author: { name: "Some", username: "app[bot]" } }),
      commit("Human (#2)"),
    ]),
    repo,
  );
  assert.equal(messages.length, 1);
  assert.equal(messages[0].embeds[0].title, "Merged: Human (#2)");
});

test("more than ten commits are summarised, oldest first", () => {
  const commits = Array.from({ length: 13 }, (_, i) => commit(`Change ${i + 1}`));
  const messages = messagesFor("push", push(commits), repo);
  assert.equal(messages.length, 10);
  assert.equal(messages[0].embeds[0].title, "Merged: Change 1");
  assert.equal(messages[8].embeds[0].title, "Merged: Change 9");
  assert.equal(messages[9].embeds[0].title, "and 4 more changes");
});

test("long titles are cut to 256 characters", () => {
  const [message] = messagesFor("push", push([commit("x".repeat(400))]), repo);
  assert.equal(message.embeds[0].title.length, 256);
});

test("other branches and unknown events post nothing", () => {
  assert.deepEqual(messagesFor("push", push([commit("A")], "refs/heads/dev"), repo), []);
  assert.deepEqual(messagesFor("issues", { action: "opened" }, repo), []);
  assert.deepEqual(messagesFor("push", {}, repo), []);
});
