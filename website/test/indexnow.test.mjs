// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  builtFile,
  changedUrls,
  findKey,
  parseUrlList,
  sitemapUrls,
  submit,
  submitBody,
} from "../indexnow.mjs";

const HOME = "https://orielos.org/";
const NEWS = "https://orielos.org/news/";
const OLD = "https://orielos.org/old/";

// The live site as a map of address to body; anything else is a 404.
function liveSite(pages, sitemap = []) {
  return {
    fetchLive: async (url) => (url in pages ? { status: 200, body: pages[url] } : { status: 404, body: "" }),
    liveSitemapUrls: async () => sitemap,
  };
}

const quiet = { warn: () => {} };

test("sitemapUrls reads the addresses back", () => {
  const xml = "<urlset><url><loc>https://orielos.org/</loc></url>\n<url><loc> https://orielos.org/?a=1&amp;b=2 </loc></url></urlset>";
  assert.deepEqual(sitemapUrls(xml), [HOME, "https://orielos.org/?a=1&b=2"]);
});

test("builtFile finds the file behind an address", () => {
  assert.equal(builtFile(HOME), "index.html");
  assert.equal(builtFile(NEWS), "news/index.html");
  assert.equal(builtFile("https://orielos.org/press.html"), "press.html");
});

test("changedUrls skips unchanged pages and lists changed and new ones", async () => {
  const built = { [HOME]: "home v2", [NEWS]: "news" };
  const urls = await changedUrls({
    sitemapUrls: [HOME, NEWS],
    readBuilt: async (url) => built[url],
    ...liveSite({ [HOME]: "home v1" }, [HOME]),
    ...quiet,
  });
  assert.deepEqual(urls, [HOME, NEWS]);

  const none = await changedUrls({
    sitemapUrls: [HOME],
    readBuilt: async () => "same",
    ...liveSite({ [HOME]: "same" }, [HOME]),
    ...quiet,
  });
  assert.deepEqual(none, []);
});

test("changedUrls lists pages the new sitemap dropped", async () => {
  const urls = await changedUrls({
    sitemapUrls: [HOME],
    readBuilt: async () => "same",
    ...liveSite({ [HOME]: "same" }, [HOME, OLD, "https://example.com/elsewhere"]),
    ...quiet,
  });
  assert.deepEqual(urls, [OLD]);
});

test("changedUrls sends nothing when the live site can't be reached", async () => {
  const warnings = [];
  const urls = await changedUrls({
    sitemapUrls: [HOME],
    readBuilt: async () => "page",
    fetchLive: async () => {
      throw new Error("getaddrinfo ENOTFOUND orielos.org");
    },
    liveSitemapUrls: async () => [],
    warn: (message) => warnings.push(message),
  });
  assert.deepEqual(urls, []);
  assert.match(warnings[0], /ENOTFOUND/);
});

test("submitBody names the host, the key and where the key file is", () => {
  const key = "a".repeat(32);
  assert.deepEqual(submitBody(key, [HOME]), {
    host: "orielos.org",
    key,
    keyLocation: `https://orielos.org/${key}.txt`,
    urlList: [HOME],
  });
});

test("submit sends only orielos.org addresses and never throws", async () => {
  const sent = [];
  const logs = [];
  const warnings = [];
  const fetch = async (url, options) => {
    sent.push({ url, body: JSON.parse(options.body) });
    return { status: 202 };
  };
  const key = "a".repeat(32);
  await submit({
    key,
    urls: [HOME, "https://example.com/"],
    fetch,
    log: (message) => logs.push(message),
    warn: (message) => warnings.push(message),
  });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].url, "https://api.indexnow.org/indexnow");
  assert.deepEqual(sent[0].body.urlList, [HOME]);
  assert.match(logs[0], /accepted 1 page\(s\) \(status 202\)/);
  assert.match(warnings[0], /example\.com/);

  const rejected = [];
  await submit({ key, urls: [HOME], fetch: async () => ({ status: 403 }), log: () => {}, warn: (m) => rejected.push(m) });
  assert.match(rejected[0], /answered 403/);

  const offline = [];
  const failing = async () => {
    throw new Error("socket hang up");
  };
  await submit({ key, urls: [HOME], fetch: failing, log: () => {}, warn: (m) => offline.push(m) });
  assert.match(offline[0], /socket hang up/);

  let called = false;
  await submit({ key, urls: [], fetch: async () => (called = true), log: () => {}, warn: () => {} });
  assert.equal(called, false);
});

test("parseUrlList accepts an empty value or a JSON array of strings", () => {
  assert.deepEqual(parseUrlList(undefined), []);
  assert.deepEqual(parseUrlList(""), []);
  assert.deepEqual(parseUrlList(`["${HOME}"]`), [HOME]);
  assert.throws(() => parseUrlList('{"a": 1}'), /JSON array/);
  assert.throws(() => parseUrlList("[1]"), /JSON array/);
});

test("findKey reads the site's key file and checks it", async () => {
  const publicDir = fileURLToPath(new URL("../public/", import.meta.url));
  const key = await findKey(publicDir);
  assert.match(key, /^[0-9a-f]{32}$/);

  const dir = await mkdtemp(path.join(tmpdir(), "indexnow-"));
  try {
    await assert.rejects(findKey(dir), /found 0/);
    await writeFile(path.join(dir, `${"b".repeat(32)}.txt`), "wrong");
    await assert.rejects(findKey(dir), /must contain its own name/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
