// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import test from "node:test";

import { fetchCommitCountByAuthor, fetchStars } from "../src/github.js";
import {
  firstContributionCandidates,
  messagesFor,
  planStarPost,
  welcomeMessage,
  withTestersPing,
} from "../src/posts.js";
import { dedupeTesters, parseRecord, planTesters, serialiseRecord } from "../src/store.js";

const repo = "ncjsvr/OrielOS";
const person = { login: "alice", type: "User", html_url: "https://github.com/alice" };
const bot = { login: "dependabot[bot]", type: "Bot", html_url: "https://github.com/apps/dependabot" };

const issue = {
  number: 12,
  title: "Fix the_thing",
  state: "open",
  html_url: "https://github.com/ncjsvr/OrielOS/issues/12",
  user: person,
  labels: [{ name: "type: bug" }],
  created_at: "2026-10-25T10:00:00Z",
  updated_at: "2026-10-25T12:00:00Z",
};

test("an issue opened with the good first issue label says so in its title", () => {
  const labelled = { ...issue, labels: [{ name: "Good First Issue" }] };
  const [message] = messagesFor("issues", { action: "opened", issue: labelled }, repo);
  assert.equal(message.embeds[0].title, "Good first issue #12: Fix the\\_thing");
  const [plain] = messagesFor("issues", { action: "opened", issue }, repo);
  assert.equal(plain.embeds[0].title, "Issue #12: Fix the\\_thing");
});

test("a good first issue label added later is posted", () => {
  const [message] = messagesFor(
    "issues",
    { action: "labeled", label: { name: "good first issue" }, issue },
    repo,
  );
  assert.equal(message.embeds[0].title, "Good first issue #12: Fix the\\_thing");
  assert.equal(message.embeds[0].url, issue.html_url);
  assert.equal(message.embeds[0].timestamp, issue.updated_at);
  assert.equal(message.embeds[0].fields, undefined);
});

test("other labels, closed issues, bots and labels given at creation are not posted", () => {
  const event = (overrides, label = "good first issue") =>
    messagesFor("issues", { action: "labeled", label: { name: label }, issue: { ...issue, ...overrides } }, repo);
  assert.deepEqual(event({}, "type: bug"), []);
  assert.deepEqual(event({ state: "closed" }), []);
  assert.deepEqual(event({ user: bot }), []);
  assert.deepEqual(event({ updated_at: "2026-10-25T10:01:00Z" }), []);
});

function push(commits, ref = "refs/heads/main") {
  return { ref, commits };
}

function commit(message, username, name = username) {
  return {
    message,
    url: "https://github.com/ncjsvr/OrielOS/commit/abc",
    timestamp: "2026-10-25T12:00:00Z",
    author: { name, username },
  };
}

test("first contribution candidates skip bots, missing usernames and repeats", () => {
  const candidates = firstContributionCandidates(
    push([
      commit("feat: a (#3)", "alice"),
      commit("fix: b", "Alice"),
      commit("build: bump", "dependabot[bot]"),
      { message: "chore: c", author: { name: "No account" } },
      commit("docs: d", "bob"),
    ]),
  );
  assert.deepEqual(
    candidates.map((candidate) => candidate.username),
    ["alice", "bob"],
  );
  assert.deepEqual(firstContributionCandidates(push([commit("x", "carol")], "refs/heads/dev")), []);
});

test("a welcome links the pull request, or the commit when there is no pull request", () => {
  const [withPull] = firstContributionCandidates(push([commit("feat: add a thing (#7)", "alice")]));
  const message = welcomeMessage(withPull, repo);
  assert.equal(message.embeds[0].title, "Welcome, alice: first contribution merged");
  assert.equal(message.embeds[0].description, "feat: add a thing (#7)");
  assert.equal(message.embeds[0].url, "https://github.com/ncjsvr/OrielOS/pull/7");
  assert.deepEqual(message.embeds[0].author, { name: "alice", url: "https://github.com/alice" });
  const [direct] = firstContributionCandidates(push([commit("fix: tidy", "bob")]));
  assert.equal(welcomeMessage(direct, repo).embeds[0].url, "https://github.com/ncjsvr/OrielOS/commit/abc");
});

test("star milestones: none on the first run, one at a time, never back", () => {
  assert.deepEqual(planStarPost(130, undefined, repo), { post: null, announced: 100 });
  assert.deepEqual(planStarPost(7, undefined, repo), { post: null, announced: 0 });
  const crossed = planStarPost(26, 10, repo);
  assert.equal(crossed.announced, 25);
  assert.equal(crossed.post.embeds[0].title, "OrielOS has 25 stars on GitHub");
  assert.equal(crossed.post.embeds[0].url, "https://github.com/ncjsvr/OrielOS/stargazers");
  const jumped = planStarPost(1200, 100, repo);
  assert.equal(jumped.announced, 1000);
  assert.equal(jumped.post.embeds[0].title, "OrielOS has 1,000 stars on GitHub");
  assert.deepEqual(planStarPost(90, 100, repo), { post: null, announced: 100 });
  assert.deepEqual(planStarPost(9, 0, repo), { post: null, announced: 0 });
});

const discussion = {
  title: "How do I add a printer?",
  html_url: "https://github.com/ncjsvr/OrielOS/discussions/9",
  user: { login: "bob", type: "User" },
  category: { slug: "q-a", name: "Q&A" },
  answer_chosen_at: "2026-10-25T13:00:00Z",
};
const answer = {
  html_url: "https://github.com/ncjsvr/OrielOS/discussions/9#discussioncomment-1",
  user: person,
  created_at: "2026-10-25T12:30:00Z",
};

test("an answered question links the answer and credits the answerer", () => {
  const [message] = messagesFor("discussion", { action: "answered", discussion, answer }, repo);
  const [embed] = message.embeds;
  assert.equal(embed.title, "Answered: How do I add a printer?");
  assert.equal(embed.url, answer.html_url);
  assert.equal(embed.author.name, "alice");
  assert.deepEqual(embed.fields, [{ name: "Question by", value: "bob" }]);
  assert.equal(embed.timestamp, answer.created_at);
  assert.equal(message.mentions, undefined);
});

test("answers by bots, or without an answer, are not posted", () => {
  assert.deepEqual(messagesFor("discussion", { action: "answered", discussion, answer: { ...answer, user: bot } }, repo), []);
  assert.deepEqual(messagesFor("discussion", { action: "answered", discussion }, repo), []);
});

test("a full release still pings everyone and is crossposted", () => {
  const release = { name: "1.0", html_url: "https://github.com/ncjsvr/OrielOS/releases/tag/v1.0", prerelease: false };
  const [message] = messagesFor("release", { action: "published", release }, repo);
  assert.equal(message.content, "@everyone");
  assert.deepEqual(message.mentions, { parse: ["everyone"] });
  assert.equal(message.crosspost, true);
  assert.equal(message.pingTesters, undefined);
});

test("the test build marker becomes a Testers mention, or disappears without the role", () => {
  const messages = [{ embeds: [], crosspost: true, pingTesters: true }, { embeds: [] }];
  const [pinged, plain] = withTestersPing(messages, "555");
  assert.equal(pinged.content, "<@&555>");
  assert.deepEqual(pinged.mentions, { roles: ["555"] });
  assert.equal("pingTesters" in pinged, false);
  assert.deepEqual(plain, { embeds: [] });
  const [quiet] = withTestersPing(messages, null);
  assert.deepEqual(quiet, { embeds: [], crosspost: true });
});

test("feed records keep stars when valid", () => {
  const feed = { kind: "feed", pr: 4, stars: 25 };
  assert.deepEqual(parseRecord(serialiseRecord(feed)), feed);
  assert.deepEqual(parseRecord(serialiseRecord({ kind: "feed", pr: 4 })), { kind: "feed", pr: 4 });
  assert.deepEqual(parseRecord('{"kind":"feed","pr":4,"stars":-1}'), { kind: "feed", pr: 4 });
  assert.deepEqual(parseRecord('{"kind":"feed","pr":4,"stars":"25"}'), { kind: "feed", pr: 4 });
});

test("tester records round trip, and bad ones are ignored", () => {
  const tester = { kind: "tester", discord: "100" };
  assert.deepEqual(parseRecord(serialiseRecord(tester)), tester);
  assert.equal(parseRecord('{"kind":"tester","discord":""}'), null);
  assert.equal(parseRecord('{"kind":"tester","discord":100}'), null);
});

test("planTesters adds new reactors and drops records whose reaction is gone", () => {
  const testers = [
    { kind: "tester", discord: "1", id: "m1" },
    { kind: "tester", discord: "2", id: "m2" },
  ];
  const plan = planTesters(new Set(["2", "3"]), testers);
  assert.deepEqual(plan.add, ["3"]);
  assert.deepEqual(plan.remove, [testers[0]]);
  assert.deepEqual(planTesters(new Set(), []), { add: [], remove: [] });
});

test("dedupeTesters keeps the newest record for each member", () => {
  const newest = { kind: "tester", discord: "1", id: "m3" };
  const older = { kind: "tester", discord: "1", id: "m1" };
  const other = { kind: "tester", discord: "2", id: "m2" };
  assert.deepEqual(dedupeTesters([newest, other, older]), { keep: [newest, other], drop: [older] });
});

function fakeFetch(body, status = 200) {
  const calls = [];
  const fetchFn = async (url) => {
    calls.push(url);
    return { ok: status >= 200 && status < 300, status, json: async () => body };
  };
  return { calls, fetchFn };
}

test("fetchCommitCountByAuthor asks main for the author's commits and caps at two", async () => {
  const { calls, fetchFn } = fakeFetch([{}, {}]);
  assert.equal(await fetchCommitCountByAuthor(repo, "alice", "t", fetchFn), 2);
  assert.match(calls[0], /\/repos\/ncjsvr\/OrielOS\/commits\?sha=main&author=alice&per_page=2$/);
  assert.equal(await fetchCommitCountByAuthor(repo, "bob", "", fakeFetch([{}]).fetchFn), 1);
  await assert.rejects(fetchCommitCountByAuthor(repo, "x", "", fakeFetch({}, 500).fetchFn), /500/);
});

test("fetchStars reads the star count", async () => {
  assert.equal(await fetchStars(repo, "", fakeFetch({ stargazers_count: 42 }).fetchFn), 42);
  await assert.rejects(fetchStars(repo, "", fakeFetch({}).fetchFn), /unexpected/);
});
