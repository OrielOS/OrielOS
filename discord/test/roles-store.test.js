// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import test from "node:test";

import { desiredRoles, roleChanges } from "../src/roles.js";
import {
  dedupeLinks,
  linksToMove,
  linksToUnlink,
  parseRecord,
  planLink,
  serialiseRecord,
} from "../src/store.js";

const roleIds = { maintainer: "R1", contributor: "R2" };

test("desiredRoles matches the login and the GitHub ID", () => {
  const who = { maintainers: ["alice"], contributorIds: [7] };
  assert.deepEqual(desiredRoles({ login: "Alice", github: 1 }, who), {
    maintainer: true,
    contributor: false,
  });
  assert.deepEqual(desiredRoles({ login: "bob", github: 7 }, who), {
    maintainer: false,
    contributor: true,
  });
});

test("roleChanges adds and removes only the synced roles", () => {
  assert.deepEqual(
    roleChanges(["R1", "OTHER"], { maintainer: false, contributor: true }, roleIds),
    { add: ["contributor"], remove: ["maintainer"] },
  );
  assert.deepEqual(
    roleChanges(["R1", "R2", "OTHER"], { maintainer: true, contributor: true }, roleIds),
    { add: [], remove: [] },
  );
});

const link = { kind: "link", discord: "100", github: 7, login: "alice", at: "2026-01-01T00:00:00.000Z" };

test("records survive a round trip", () => {
  assert.deepEqual(parseRecord(serialiseRecord(link)), link);
  const welcome = { kind: "welcome", message: "555" };
  assert.deepEqual(parseRecord(serialiseRecord(welcome)), welcome);
  const feed = { kind: "feed", pr: 42 };
  assert.deepEqual(parseRecord(serialiseRecord(feed)), feed);
  const onMessage = { ...link, on: "555" };
  assert.deepEqual(parseRecord(serialiseRecord(onMessage)), onMessage);
});

test("only a reaction removed from the link's own welcome message unlinks", () => {
  const current = { ...link, discord: "1", on: "W2" };
  const older = { ...link, discord: "2", on: "W1" };
  const legacy = { ...link, discord: "3" };
  const links = [current, older, legacy];
  assert.deepEqual(linksToUnlink(links, new Set(), "W2"), [current, legacy]);
  assert.deepEqual(linksToUnlink(links, new Set(["1", "3"]), "W2"), []);
});

test("links from an older welcome message move when the member reacts again", () => {
  const current = { ...link, discord: "1", on: "W2" };
  const older = { ...link, discord: "2", on: "W1" };
  assert.deepEqual(linksToMove([current, older], new Set(["1", "2"]), "W2"), [older]);
  assert.deepEqual(linksToMove([current, older], new Set(["1"]), "W2"), []);
});

test("unknown kinds, bad JSON and incomplete records are ignored", () => {
  assert.equal(parseRecord('{"kind":"other"}'), null);
  assert.equal(parseRecord("not json"), null);
  assert.equal(parseRecord("null"), null);
  assert.equal(parseRecord('{"kind":"link","discord":"1"}'), null);
  assert.equal(parseRecord('{"kind":"welcome"}'), null);
  assert.equal(parseRecord('{"kind":"feed","pr":-1}'), null);
  assert.equal(parseRecord('{"kind":"feed","pr":"3"}'), null);
  assert.equal(parseRecord('{"kind":"feed","pr":1.5}'), null);
});

test("planLink for a new link removes nothing", () => {
  const plan = planLink([link], { discord: "200", github: 8, login: "bob" });
  assert.deepEqual(plan, { remove: [], moved: [] });
});

test("planLink replaces a link for the same pair without moving it", () => {
  const plan = planLink([link], { discord: "100", github: 7, login: "alice" });
  assert.deepEqual(plan, { remove: [link], moved: [] });
});

test("planLink moves a GitHub account to another member", () => {
  const plan = planLink([link], { discord: "200", github: 7, login: "alice" });
  assert.deepEqual(plan, { remove: [link], moved: [link] });
});

test("dedupeLinks keeps the newest link for each ID", () => {
  const newest = { ...link, id: "3" };
  const sameDiscord = { ...link, id: "2", github: 9 };
  const sameGithub = { ...link, id: "1", discord: "300" };
  const other = { ...link, id: "0", discord: "400", github: 11 };
  const { keep, drop } = dedupeLinks([newest, sameDiscord, sameGithub, other]);
  assert.deepEqual(keep, [newest, other]);
  assert.deepEqual(drop, [sameDiscord, sameGithub]);
});
