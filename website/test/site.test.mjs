// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Builds the whole site offline into a temporary folder and checks the result.

import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { build, checkPages, gitLastModified, isNoindex, pageUrl } from "../build.mjs";

test("an offline build makes every page, the feed and the sitemap", async (t) => {
  const outDir = await mkdtemp(path.join(tmpdir(), "orielos-site-"));
  t.after(() => rm(outDir, { recursive: true, force: true }));
  const log = console.log;
  console.log = () => {};
  try {
    await build({ offline: true, outDir });
  } finally {
    console.log = log;
  }

  const expected = [
    "index.html",
    "404.html",
    "guides/index.html",
    "guides/install/index.html",
    "news/index.html",
    "news/feed.xml",
    "releases/index.html",
    "download/index.html",
    "faq/index.html",
    "credits/index.html",
    "news/orielos-v0-0-7/index.html",
    "sitemap.xml",
  ];
  for (const file of expected) assert.ok(existsSync(path.join(outDir, file)), file);
  assert.ok(!existsSync(path.join(outDir, "templates")), "templates aren't published");

  const sitemap = await readFile(path.join(outDir, "sitemap.xml"), "utf8");
  for (const url of ["/", "/guides/", "/guides/install/", "/news/", "/news/orielos-v0-0-7/", "/releases/", "/download/", "/faq/", "/credits/"]) {
    assert.ok(sitemap.includes(`<loc>https://orielos.org${url}</loc>`), url);
  }
  assert.doesNotMatch(sitemap, /404/);
  for (const [, date] of sitemap.matchAll(/<lastmod>([^<]*)<\/lastmod>/g)) {
    assert.match(date, /^\d{4}-\d{2}-\d{2}$/);
  }
  if (gitLastModified(["website/public/index.html"]).has("website/public/index.html")) {
    assert.match(sitemap, /<loc>https:\/\/orielos.org\/<\/loc><lastmod>\d{4}-\d{2}-\d{2}<\/lastmod>/);
  }

  // Every page passes the search checks again, and none is left with a marker.
  const files = (await readdir(outDir, { recursive: true }))
    .map((file) => file.replaceAll("\\", "/"))
    .filter((file) => file.endsWith(".html"));
  const pages = [];
  for (const file of files) {
    const html = await readFile(path.join(outDir, file), "utf8");
    assert.doesNotMatch(html, /<!-- (?:if|end|include):|<!-- (?:news|contributors|artwork-credits|head|content) -->|\{\{[a-z]+(?:\.[a-z]+)?\}\}/, file);
    assert.match(html, /class="site-header"/, file);
    assert.match(html, /class="site-footer"/, file);
    if (!isNoindex(html)) pages.push({ file, url: pageUrl(file), html });
  }
  assert.doesNotThrow(() => checkPages(pages));

  const install = await readFile(path.join(outDir, "guides/install/index.html"), "utf8");
  assert.match(install, /<title>Install OrielOS · OrielOS guides<\/title>/);
  assert.match(install, /<a href="\/guides\/" aria-current="page">Guides<\/a>/);
  const download = await readFile(path.join(outDir, "download/index.html"), "utf8");
  assert.match(download, /<a href="\/download\/" aria-current="page">Download<\/a>/);
  assert.match(download, /Nothing to download yet/);
  const releases = await readFile(path.join(outDir, "releases/index.html"), "utf8");
  assert.match(releases, /No releases yet/);
  const feed = await readFile(path.join(outDir, "news/feed.xml"), "utf8");
  assert.match(feed, /<feed xmlns="http:\/\/www\.w3\.org\/2005\/Atom"/);
});
