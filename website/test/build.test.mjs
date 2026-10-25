// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  escapeHtml,
  formatSize,
  isHuman,
  isoFrom,
  nextLink,
  releaseFrom,
  renderPage,
} from "../build.mjs";

const template = await readFile(
  fileURLToPath(new URL("../public/index.html", import.meta.url)),
  "utf8",
);

const leftovers = /<!-- (?:if|end):|<!-- contributors -->|\{\{(?:release|iso)\./;

test("renders without a release or contributors", () => {
  const html = renderPage(template, { contributors: [], release: null });
  assert.doesNotMatch(html, leftovers);
  assert.match(html, /Nothing to download yet\./);
  assert.match(html, /Follow on GitHub/);
  assert.match(html, /graphs\/contributors/);
  assert.doesNotMatch(html, /class="people"/);
});

test("renders a release without an installer", () => {
  const release = { name: "OrielOS 1.0", url: "https://github.com/ncjsvr/OrielOS/releases/tag/v1.0", iso: null };
  const html = renderPage(template, { contributors: [], release });
  assert.doesNotMatch(html, leftovers);
  assert.match(html, /OrielOS 1\.0 is out\./);
  assert.match(html, /Follow on GitHub/);
  assert.doesNotMatch(html, /In early development/);
  assert.doesNotMatch(html, /Download the installer/);
});

test("renders a release with its installer", () => {
  const iso = {
    url: "https://github.com/ncjsvr/OrielOS/releases/download/v1.0/orielos-installer-x86_64.iso",
    size: "1.2 GB",
    sha256: "a".repeat(64),
  };
  const release = { name: "OrielOS 1.0", url: "https://github.com/ncjsvr/OrielOS/releases/tag/v1.0", iso };
  const html = renderPage(template, { contributors: [], release });
  assert.doesNotMatch(html, leftovers);
  assert.match(html, /Download OrielOS 1\.0/);
  assert.ok(html.includes(`href="${iso.url}"`));
  assert.ok(html.includes(release.url));
  assert.ok(html.includes("Installer, 1.2 GB."));
  assert.ok(html.includes(`<code translate="no">${iso.sha256}</code>`));
  assert.doesNotMatch(html, /Nothing to download yet/);
  assert.doesNotMatch(html, /Follow on GitHub/);
});

test("leaves out the checksum line when the release has none", () => {
  const iso = { url: "https://github.com/a/b/releases/download/v1/x.iso", size: "1.2 GB", sha256: "" };
  const release = { name: "OrielOS 1.0", url: "https://github.com/a/b/releases/tag/v1", iso };
  const html = renderPage(template, { contributors: [], release });
  assert.doesNotMatch(html, leftovers);
  assert.doesNotMatch(html, /SHA-256/);
});

test("renders contributors", () => {
  const contributors = [
    { login: "alice", avatar: "avatars/1.png" },
    { login: "bob", avatar: "favicon.svg" },
  ];
  const html = renderPage(template, { contributors, release: null });
  assert.doesNotMatch(html, leftovers);
  assert.match(html, /class="people"/);
  assert.match(html, /<a href="https:\/\/github\.com\/alice"><img src="avatars\/1\.png"/);
  assert.match(html, /<span class="person-name">bob<\/span>/);
  assert.doesNotMatch(html, /graphs\/contributors/);
});

test("escapes hostile values", () => {
  const login = 'a"<b>&';
  const html = renderPage(template, {
    contributors: [{ login, avatar: "favicon.svg" }],
    release: {
      name: "<x>",
      url: "https://github.com/a/b?c=1&d='2'",
      iso: { url: "https://github.com/a/b/x.iso", size: "1.0 GB", sha256: "" },
    },
  });
  assert.ok(html.includes(`href="https://github.com/${encodeURIComponent(login)}"`));
  assert.ok(html.includes("a&quot;&lt;b&gt;&amp;</span>"));
  assert.ok(!html.includes("<b>"));
  assert.ok(html.includes("&lt;x&gt;"));
  assert.ok(html.includes("c=1&amp;d=&#39;2&#39;"));
});

test("escapeHtml escapes all five characters", () => {
  assert.equal(escapeHtml(`&<>"'`), "&amp;&lt;&gt;&quot;&#39;");
});

test("isHuman filters bots and malformed entries", () => {
  assert.equal(isHuman({ id: 1, login: "alice", type: "User" }), true);
  assert.equal(isHuman({ id: 2, login: "robot", type: "Bot" }), false);
  assert.equal(isHuman({ id: 3, login: "dependabot[bot]", type: "User" }), false);
  assert.equal(isHuman({ id: "4", login: "x" }), false);
  assert.equal(isHuman({ login: "x" }), false);
  assert.equal(isHuman({ id: 5, login: "" }), false);
  assert.equal(isHuman(null), false);
});

test("releaseFrom validates the URL and falls back to the tag", () => {
  const repo = "ncjsvr/OrielOS";
  assert.deepEqual(
    releaseFrom({ name: "One", tag_name: "v1", html_url: "https://evil.example/x" }, repo),
    { name: "One", url: "https://github.com/ncjsvr/OrielOS/releases/latest", iso: null },
  );
  assert.deepEqual(
    releaseFrom({ name: "", tag_name: "v1", html_url: "https://github.com/ncjsvr/OrielOS/releases/tag/v1" }, repo),
    { name: "v1", url: "https://github.com/ncjsvr/OrielOS/releases/tag/v1", iso: null },
  );
});

test("isoFrom picks the uploaded installer and reads its checksum", () => {
  const sha = "0123456789abcdef".repeat(4);
  const assets = [
    { name: "SHA256SUMS", state: "uploaded", size: 120, browser_download_url: "https://github.com/a/b/releases/download/v1/SHA256SUMS" },
    { name: "orielos-installer-x86_64.ISO", state: "uploaded", size: 1_234_567_890, digest: `sha256:${sha}`, browser_download_url: "https://github.com/a/b/releases/download/v1/orielos-installer-x86_64.ISO" },
  ];
  assert.deepEqual(isoFrom(assets), {
    url: "https://github.com/a/b/releases/download/v1/orielos-installer-x86_64.ISO",
    size: "1.2 GB",
    sha256: sha,
  });
  assert.equal(isoFrom([{ ...assets[1], state: "starter" }]), null);
  assert.equal(isoFrom([{ ...assets[1], browser_download_url: "https://evil.example/x.iso" }]), null);
  assert.equal(isoFrom([{ ...assets[1], digest: "md5:abc" }]).sha256, "");
  assert.equal(isoFrom(undefined), null);
});

test("formatSize uses GB and MB", () => {
  assert.equal(formatSize(1_234_567_890), "1.2 GB");
  assert.equal(formatSize(734_003_200), "734 MB");
  assert.equal(formatSize(10), "1 MB");
});

test("nextLink finds the next page", () => {
  const header =
    '<https://api.github.com/x?page=1>; rel="prev", <https://api.github.com/x?page=3>; rel="next", <https://api.github.com/x?page=9>; rel="last"';
  assert.equal(nextLink(header), "https://api.github.com/x?page=3");
  assert.equal(nextLink('<https://api.github.com/x?page=1>; rel="prev"'), null);
  assert.equal(nextLink(null), null);
  assert.equal(nextLink(""), null);
});

test("renderPage throws on an unknown leftover marker", () => {
  assert.throws(
    () => renderPage("<p><!-- if:typo -->x<!-- end:typo --></p>", { contributors: [], release: null }),
    /unresolved marker/,
  );
  assert.throws(
    () => renderPage("<p>{{release.nme}}</p>", { contributors: [], release: null }),
    /unresolved marker/,
  );
});
