// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import test from "node:test";

import { clean, formatSize, isoFrom, messagesFor, planPullPosts, truncate } from "../src/posts.js";

const repo = "OrielOS/OrielOS";

const release = {
  name: "1.0",
  tag_name: "v1.0",
  html_url: "https://github.com/OrielOS/OrielOS/releases/tag/v1.0",
  body: "Notes for *everyone*",
  draft: false,
  prerelease: false,
  assets: [
    { name: "notes.txt", size: 10, browser_download_url: "https://github.com/x/notes.txt" },
    {
      name: "OrielOS.iso",
      state: "uploaded",
      size: 2_400_000_000,
      browser_download_url: "https://github.com/OrielOS/OrielOS/releases/download/v1.0/OrielOS.iso",
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
      value: "[Download the ISO](https://github.com/OrielOS/OrielOS/releases/download/v1.0/OrielOS.iso) (2.4 GB)",
    },
  ]);
});

test("a pre-release is a test build that asks for the Testers ping", () => {
  const [message] = messagesFor(
    "release",
    { action: "published", release: { ...release, prerelease: true, assets: [] } },
    repo,
  );
  assert.equal(message.embeds[0].title, "Test build 1.0 is ready");
  assert.equal(message.embeds[0].fields, undefined);
  assert.equal(message.pingTesters, true);
  assert.equal(message.mentions, undefined);
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

test("clean and truncate never cut an emoji in half", () => {
  assert.equal(clean(`ab${"😀".repeat(5)}`, 4), "ab…");
  assert.equal(truncate(`ab${"😀".repeat(5)}`, 4), "ab…");
  assert.equal(clean(`ab${"😀".repeat(5)}`, 5), "ab😀…");
});

test("clean never ends on a lone backslash", () => {
  assert.equal(clean("_".repeat(10), 4), "\\_…");
  assert.equal(clean("_".repeat(10), 5), "\\_\\_…");
});

const commit = (message, extra = {}) => ({
  message,
  url: `https://github.com/OrielOS/OrielOS/commit/${message.length}`,
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
  assert.equal(embed.url, "https://github.com/OrielOS/OrielOS/pull/12");
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
  assert.deepEqual(messagesFor("discussion", {}, repo), []);
  assert.deepEqual(messagesFor("push", {}, repo), []);
});

const user = { login: "alice", type: "User", html_url: "https://github.com/alice" };
const issue = {
  number: 7,
  title: "Fix *the* snake_case bug",
  html_url: "https://github.com/OrielOS/OrielOS/issues/7",
  user,
  labels: [{ name: "bug" }, { name: "good_first" }],
  body: "secret body",
  created_at: "2026-05-01T10:00:00Z",
};

test("a new issue becomes one embed with its labels", () => {
  const [message] = messagesFor("issues", { action: "opened", issue }, repo);
  const [embed] = message.embeds;
  assert.equal(embed.title, "Issue #7: Fix \\*the\\* snake\\_case bug");
  assert.equal(embed.url, issue.html_url);
  assert.deepEqual(embed.author, { name: "alice", url: "https://github.com/alice" });
  assert.deepEqual(embed.fields, [{ name: "Labels", value: "bug, good\\_first" }]);
  assert.equal(embed.timestamp, "2026-05-01T10:00:00Z");
  assert.equal(embed.color, 0x3a66f0);
  assert.equal(embed.description, undefined);
  assert.equal(JSON.stringify(message).includes("secret body"), false);
});

test("an issue without labels has no fields", () => {
  const [message] = messagesFor("issues", { action: "opened", issue: { ...issue, labels: [] } }, repo);
  assert.equal(message.embeds[0].fields, undefined);
});

test("bot issues and other issue actions are skipped", () => {
  const bot = { login: "dependabot[bot]", type: "Bot" };
  assert.deepEqual(messagesFor("issues", { action: "opened", issue: { ...issue, user: bot } }, repo), []);
  const named = { login: "app[bot]", type: "User" };
  assert.deepEqual(messagesFor("issues", { action: "opened", issue: { ...issue, user: named } }, repo), []);
  assert.deepEqual(messagesFor("issues", { action: "closed", issue }, repo), []);
});

const discussion = {
  number: 3,
  title: "How do I _do_ it?",
  html_url: "https://github.com/OrielOS/OrielOS/discussions/3",
  user,
  category: { name: "Q&A", slug: "q-a" },
  created_at: "2026-05-02T10:00:00Z",
};

test("a new Q&A discussion is a question", () => {
  const [message] = messagesFor("discussion", { action: "created", discussion }, repo);
  const [embed] = message.embeds;
  assert.equal(embed.title, "Question: How do I \\_do\\_ it?");
  assert.equal(embed.url, discussion.html_url);
  assert.deepEqual(embed.fields, [{ name: "Category", value: "Q&A" }]);
  assert.equal(embed.timestamp, "2026-05-02T10:00:00Z");
});

test("other discussions are labelled as discussions; bots and other actions are skipped", () => {
  const ideas = { ...discussion, category: { name: "Ideas", slug: "ideas" } };
  const [message] = messagesFor("discussion", { action: "created", discussion: ideas }, repo);
  assert.equal(message.embeds[0].title, "Discussion: How do I \\_do\\_ it?");
  assert.deepEqual(message.embeds[0].fields, [{ name: "Category", value: "Ideas" }]);
  const bot = { ...discussion, user: { login: "x[bot]", type: "Bot" } };
  assert.deepEqual(messagesFor("discussion", { action: "created", discussion: bot }, repo), []);
  assert.deepEqual(messagesFor("discussion", { action: "answered", discussion }, repo), []);
});

test("only releases ask to be crossposted", () => {
  assert.equal(messagesFor("release", { action: "published", release }, repo)[0].crosspost, true);
  assert.equal(messagesFor("issues", { action: "opened", issue }, repo)[0].crosspost, undefined);
});

const pull = (number, extra = {}) => ({
  number,
  title: `Change ${number}`,
  html_url: `https://github.com/OrielOS/OrielOS/pull/${number}`,
  user,
  draft: false,
  created_at: "2026-05-03T10:00:00Z",
  ...extra,
});

test("the first run sets the bookmark without posting", () => {
  assert.deepEqual(planPullPosts([pull(9), pull(8)], null), { posts: [], bookmark: 9 });
  assert.deepEqual(planPullPosts([], null), { posts: [], bookmark: 0 });
});

test("only newer pull requests are posted, oldest first", () => {
  const plan = planPullPosts([pull(9), pull(8), pull(7), pull(6)], 7);
  assert.equal(plan.bookmark, 9);
  assert.deepEqual(plan.posts.map((post) => post.embeds[0].title), [
    "Pull request #8: Change 8",
    "Pull request #9: Change 9",
  ]);
  const [embed] = plan.posts[0].embeds;
  assert.equal(embed.url, "https://github.com/OrielOS/OrielOS/pull/8");
  assert.deepEqual(embed.author, { name: "alice", url: "https://github.com/alice" });
  assert.equal(plan.posts[0].crosspost, undefined);
});

test("bot pull requests are skipped but still move the bookmark; drafts are labelled", () => {
  const bot = { login: "dependabot[bot]", type: "Bot" };
  const plan = planPullPosts([pull(12, { user: bot }), pull(11, { draft: true })], 10);
  assert.equal(plan.bookmark, 12);
  assert.equal(plan.posts.length, 1);
  assert.equal(plan.posts[0].embeds[0].title, "Draft pull request #11: Change 11");
});

test("with nothing new the bookmark stays", () => {
  assert.deepEqual(planPullPosts([], 5), { posts: [], bookmark: 5 });
  assert.deepEqual(planPullPosts([pull(5)], 5), { posts: [], bookmark: 5 });
});
