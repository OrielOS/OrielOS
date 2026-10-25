// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Tells search engines through IndexNow which orielos.org pages a deploy
// changed, so they can crawl them soon instead of guessing.
//
// Usage, from the repository root:
//   node website/indexnow.mjs changed   before the deploy: compares the built
//                                       pages with the live site and writes
//                                       urls=[...] to $GITHUB_OUTPUT
//   node website/indexnow.mjs submit    after the deploy: sends the pages
//                                       listed in $INDEXNOW_URLS
//
// Network and HTTP problems only print warnings, so they never fail a deploy.

import { appendFile, readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { SITE, decodeEntities } from "./build.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const siteDir = path.join(here, "_site");
const publicDir = path.join(here, "public");

const ENDPOINT = "https://api.indexnow.org/indexnow";
const HEADERS = { "User-Agent": "orielos.org-build" };

export function sitemapUrls(xml) {
  return [...xml.matchAll(/<loc>([^<]*)<\/loc>/g)].map((match) => decodeEntities(match[1].trim()));
}

// The built file behind an address: folders are served by their index.html.
export function builtFile(url) {
  const rest = decodeURI(url.slice(`${SITE}/`.length));
  return rest === "" || rest.endsWith("/") ? `${rest}index.html` : rest;
}

export function isSiteUrl(url) {
  return typeof url === "string" && url.startsWith(`${SITE}/`);
}

// Pages that are new or differ from the live site, then pages the live
// sitemap still lists but the new one doesn't (removed). An unreachable live
// site gives no list at all rather than everything.
export async function changedUrls({ sitemapUrls, liveSitemapUrls, readBuilt, fetchLive, warn }) {
  try {
    const changed = [];
    for (const url of sitemapUrls) {
      const live = await fetchLive(url);
      if (live.status !== 200 || live.body !== (await readBuilt(url))) changed.push(url);
    }
    const current = new Set(sitemapUrls);
    for (const url of await liveSitemapUrls()) {
      if (!current.has(url) && isSiteUrl(url)) changed.push(url);
    }
    return changed;
  } catch (error) {
    warn(`Could not compare the build with ${SITE}, so no pages are sent: ${error.message}`);
    return [];
  }
}

export function submitBody(key, urls) {
  return { host: new URL(SITE).host, key, keyLocation: `${SITE}/${key}.txt`, urlList: urls };
}

// The key is public by design: search engines fetch the file to check that
// submissions come from the site.
export async function findKey(dir) {
  const names = (await readdir(dir)).filter((name) => /^[0-9a-f]{32}\.txt$/.test(name));
  if (names.length !== 1) {
    throw new Error(`Expected one IndexNow key file in ${dir}, found ${names.length}.`);
  }
  const key = names[0].slice(0, -".txt".length);
  if ((await readFile(path.join(dir, names[0]), "utf8")).trim() !== key) {
    throw new Error(`The IndexNow key file ${names[0]} must contain its own name.`);
  }
  return key;
}

export async function submit({ key, urls, fetch, log, warn }) {
  const pages = urls.filter((url) => {
    if (isSiteUrl(url)) return true;
    warn(`Not sending ${url}: it isn't on ${SITE}.`);
    return false;
  });
  if (pages.length === 0) {
    log("No pages to send.");
    return;
  }
  try {
    const response = await fetch(ENDPOINT, {
      method: "POST",
      headers: { ...HEADERS, "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify(submitBody(key, pages)),
    });
    if (response.status === 200 || response.status === 202) {
      log(`IndexNow accepted ${pages.length} page(s) (status ${response.status}).`);
    } else {
      warn(`IndexNow answered ${response.status} for ${pages.length} page(s).`);
    }
  } catch (error) {
    warn(`Could not reach IndexNow: ${error.message}`);
  }
}

export function parseUrlList(value) {
  if (value === undefined || value.trim() === "") return [];
  const urls = JSON.parse(value);
  if (!Array.isArray(urls) || !urls.every((url) => typeof url === "string")) {
    throw new Error("INDEXNOW_URLS must be a JSON array of addresses.");
  }
  return urls;
}

const log = (message) => console.log(message);
const warn = (message) => console.log(`::warning::${message}`);

async function fetchText(url) {
  const response = await fetch(url, { headers: HEADERS });
  return { status: response.status, body: response.status === 200 ? await response.text() : "" };
}

async function changedCommand() {
  const urls = await changedUrls({
    sitemapUrls: sitemapUrls(await readFile(path.join(siteDir, "sitemap.xml"), "utf8")),
    liveSitemapUrls: async () => {
      const live = await fetchText(`${SITE}/sitemap.xml`);
      return live.status === 200 ? sitemapUrls(live.body) : [];
    },
    readBuilt: (url) => readFile(path.join(siteDir, builtFile(url)), "utf8"),
    fetchLive: fetchText,
    warn,
  });
  log(urls.length > 0 ? `Changed pages:\n  ${urls.join("\n  ")}` : "No pages changed.");
  if (process.env.GITHUB_OUTPUT) {
    await appendFile(process.env.GITHUB_OUTPUT, `urls=${JSON.stringify(urls)}\n`);
  }
}

async function submitCommand() {
  const urls = parseUrlList(process.env.INDEXNOW_URLS);
  await submit({ key: await findKey(publicDir), urls, fetch, log, warn });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const commands = { changed: changedCommand, submit: submitCommand };
  const command = commands[process.argv[2]];
  if (!command) {
    console.error("Usage: node website/indexnow.mjs changed|submit");
    process.exit(2);
  }
  command().catch((error) => {
    console.error(`IndexNow step failed: ${error.message}`);
    process.exit(1);
  });
}
