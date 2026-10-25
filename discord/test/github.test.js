// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import test from "node:test";

import { fetchRecentPulls, isHuman, maintainersFromCodeowners, nextLink, nextPollStep } from "../src/github.js";

test("maintainers skip comments, blank lines, teams and emails", () => {
  const text = [
    "# Owners",
    "",
    "* @Alice @org/team bob@example.com @carol-dev # trailing",
    "docs/ @dave",
  ].join("\n");
  assert.deepEqual(maintainersFromCodeowners(text), ["alice", "carol-dev"]);
});

test("the last * rule wins", () => {
  const text = "* @first\n/docs/ @other\n*   @second @Third\n";
  assert.deepEqual(maintainersFromCodeowners(text), ["second", "third"]);
});

test("no * rule or no text means no maintainers", () => {
  assert.deepEqual(maintainersFromCodeowners("src/ @someone\n"), []);
  assert.deepEqual(maintainersFromCodeowners(""), []);
});

test("isHuman keeps people and drops bots", () => {
  assert.equal(isHuman({ id: 1, login: "alice", type: "User" }), true);
  assert.equal(isHuman({ id: 2, login: "dependabot[bot]", type: "Bot" }), false);
  assert.equal(isHuman({ id: 3, login: "x[bot]" }), false);
  assert.equal(isHuman({ id: 4, login: "bot", type: "Bot" }), false);
  assert.equal(isHuman({ id: "5", login: "alice" }), false);
  assert.equal(isHuman({ id: 6, login: "" }), false);
  assert.equal(isHuman(null), false);
});

test("nextLink finds the next page", () => {
  const header =
    '<https://api.github.com/x?page=1>; rel="prev", <https://api.github.com/x?page=3>; rel="next"';
  assert.equal(nextLink(header), "https://api.github.com/x?page=3");
  assert.equal(nextLink('<https://api.github.com/x?page=1>; rel="prev"'), null);
  assert.equal(nextLink(null), null);
});

const state = { interval: 5, deadline: 100_000, now: 10_000 };

test("nextPollStep keeps waiting while authorisation is pending", () => {
  assert.deepEqual(nextPollStep(state, { error: "authorization_pending" }), {
    done: false,
    interval: 5,
  });
});

test("nextPollStep slows down by five seconds", () => {
  assert.deepEqual(nextPollStep(state, { error: "slow_down" }), { done: false, interval: 10 });
});

test("nextPollStep returns the token on success", () => {
  assert.deepEqual(nextPollStep(state, { access_token: "t", token_type: "bearer" }), {
    done: true,
    token: "t",
  });
});

test("nextPollStep gives up on expiry, denial and unknown errors", () => {
  assert.deepEqual(nextPollStep(state, { error: "expired_token" }), {
    done: true,
    failure: "expired_token",
  });
  assert.deepEqual(nextPollStep(state, { error: "access_denied" }), {
    done: true,
    failure: "access_denied",
  });
  assert.deepEqual(nextPollStep(state, {}), { done: true, failure: "unknown" });
});

test("nextPollStep stops at the deadline", () => {
  const late = { ...state, now: 100_000 };
  assert.deepEqual(nextPollStep(late, { error: "authorization_pending" }), {
    done: true,
    failure: "expired",
  });
  assert.deepEqual(nextPollStep(late, { error: "slow_down" }), { done: true, failure: "expired" });
});

test("fetchRecentPulls returns the list and rejects bad answers", async () => {
  let url;
  const ok = async (input) => {
    url = input;
    return { ok: true, json: async () => [{ number: 1 }] };
  };
  assert.deepEqual(await fetchRecentPulls("a/b", "t", ok), [{ number: 1 }]);
  assert.match(url, /\/repos\/a\/b\/pulls\?state=all&sort=created&direction=desc&per_page=30$/);
  await assert.rejects(fetchRecentPulls("a/b", "t", async () => ({ ok: false, status: 403 })), /403/);
  await assert.rejects(
    fetchRecentPulls("a/b", "t", async () => ({ ok: true, json: async () => ({}) })),
    /unexpected/,
  );
});
