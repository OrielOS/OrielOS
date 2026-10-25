// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  checkPages,
  escapeHtml,
  formatSize,
  isHuman,
  isNoindex,
  isoFrom,
  nextLink,
  pageUrl,
  readHead,
  releaseFrom,
  renderPage,
  sitemapXml,
} from "../build.mjs";

const readPublic = (name) => readFile(fileURLToPath(new URL(`../public/${name}`, import.meta.url)), "utf8");
const template = await readPublic("index.html");

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

// A page that passes every search check, for the tests to break one part at a time.
function page({ url = "https://orielos.org/", title = "A page", description = "What the page is about.", head = "", body = "" } = {}) {
  return `<!doctype html><html><head>
<title>${title}</title>
<meta name="description" content="${description}">
<link rel="canonical" href="${url}">
<meta property="og:title" content="${title}">
<meta property="og:description" content="${description}">
<meta property="og:url" content="${url}">
<meta property="og:image" content="https://orielos.org/images/open-graph.png">
<meta property="og:image:alt" content="A picture">
${head}</head><body>${body}</body></html>`;
}

const check = (...pages) =>
  checkPages(pages.map((html, index) => ({ file: `page-${index}.html`, url: readHead(html).canonical, html })));

test("the home page passes the search checks", () => {
  const html = renderPage(template, { contributors: [], release: null });
  assert.doesNotThrow(() => checkPages([{ file: "index.html", url: "https://orielos.org/", html }]));
  const { scripts, titles } = readHead(html);
  assert.equal(titles[0], "OrielOS: a Linux desktop tuned for gaming and development");
  const data = JSON.parse(scripts.find((script) => script.type === "application/ld+json").body);
  const site = data["@graph"].find((node) => node["@type"] === "WebSite");
  assert.equal(site.name, "OrielOS");
  assert.equal(site.url, "https://orielos.org/");
  assert.equal(isNoindex(html), false);
});

test("the not-found page is kept out of search", async () => {
  assert.equal(isNoindex(await readPublic("404.html")), true);
});

test("checkPages reports each missing or wrong part", () => {
  assert.doesNotThrow(() => check(page()));
  assert.throws(() => check(page().replace(/<title>.*<\/title>/, "")), /needs exactly one <title>/);
  assert.throws(() => check(page({ title: "x".repeat(71) })), /title has 71 characters/);
  assert.throws(() => check(page().replace(/<meta name="description"[^>]*>/, "")), /needs a <meta name="description">/);
  assert.throws(() => check(page({ description: "x".repeat(161) })), /description has 161 characters/);
  assert.throws(
    () => checkPages([{ file: "a.html", url: "https://orielos.org/a.html", html: page() }]),
    /canonical link should be https:\/\/orielos\.org\/a\.html/,
  );
  assert.throws(
    () => check(page().replace('og:url" content="https://orielos.org/"', 'og:url" content="https://example.com/"')),
    /og:url should be/,
  );
  assert.throws(() => check(page().replace(/<meta property="og:image:alt"[^>]*>/, "")), /needs og:image:alt/);
  assert.throws(
    () => check(page().replace("https://orielos.org/images", "https://example.com/images")),
    /og:image should be on https:\/\/orielos\.org/,
  );
});

test("checkPages wants alt text on every image", () => {
  assert.doesNotThrow(() => check(page({ body: '<img src="a.png" alt="A diagram">' })));
  assert.throws(() => check(page({ body: '<img src="a.png">' })), /an <img> has no alt text: a\.png/);
  assert.throws(() => check(page({ body: '<img src="b.png" alt="">' })), /an <img> has no alt text: b\.png/);
  assert.throws(() => check(page({ body: "<img alt=' ' src=c.png>" })), /an <img> has no alt text: c\.png/);
});

test("the home page with contributors gives every image alt text", () => {
  const contributors = [{ login: "alice", avatar: "avatars/1.png" }];
  const html = renderPage(template, { contributors, release: null });
  assert.doesNotThrow(() => checkPages([{ file: "index.html", url: "https://orielos.org/", html }]));
  assert.match(html, /<img src="avatars\/1\.png" alt="alice’s avatar"/);
  assert.doesNotMatch(html, /alt=""/);
});

test("the footer shows the live Best Practices badge, the only image from another site", () => {
  const html = renderPage(template, { contributors: [], release: null });
  assert.match(
    html,
    /<a href="https:\/\/www\.bestpractices\.dev\/projects\/15906"><img src="https:\/\/www\.bestpractices\.dev\/projects\/15906\/badge" alt="[^"]+"/,
  );
  const csp = /http-equiv="Content-Security-Policy" content="([^"]*)"/.exec(html)[1];
  const imgSrc = csp.split(";").map((part) => part.trim()).find((part) => part.startsWith("img-src"));
  assert.equal(imgSrc, "img-src 'self' https://www.bestpractices.dev");
  const outside = [...html.matchAll(/<img\b[^>]*src="(https?:[^"]*)"/g)].map((match) => match[1]);
  assert.deepEqual(outside, ["https://www.bestpractices.dev/projects/15906/badge"]);
});

test("the home page has share links that only navigate", () => {
  const html = renderPage(template, { contributors: [], release: null });
  const links = [...html.matchAll(/<a\b[^>]*aria-label="(Share[^"]*)"[^>]*href="([^"]*)"/g)].map(([, label, href]) => ({
    label,
    href: href.replaceAll("&amp;", "&"),
  }));
  assert.deepEqual(
    links.map((link) => link.label),
    ["Share on X", "Share on Bluesky", "Share on Reddit", "Share on Facebook", "Share by email"],
  );
  for (const { href } of links) {
    assert.match(href, /^(https:\/\/|mailto:)/);
    assert.match(decodeURIComponent(href), /https:\/\/orielos\.org\//);
  }
});

test("checkPages allows structured data but no scripts that run", () => {
  assert.doesNotThrow(() => check(page({ head: '<script type="application/ld+json">{"a": 1}</script>' })));
  assert.throws(() => check(page({ head: "<script>alert(1)</script>" })), /browsers would run/);
  assert.throws(() => check(page({ head: '<script type="module" src="x.js"></script>' })), /browsers would run/);
  assert.throws(() => check(page({ head: "<script>alert(1)</script >" })), /browsers would run/);
  assert.throws(() => check(page({ head: "<SCRIPT>alert(1)</SCRIPT foo>" })), /browsers would run/);
  assert.throws(() => check(page({ head: "<script>alert(1)" })), /browsers would run/);
  assert.throws(() => check(page({ head: '<script type="application/ld+json">{"a": }</script>' })), /isn't valid JSON/);
});

test("checkPages finds pages that share a title, description or address", () => {
  const news = { url: "https://orielos.org/news/" };
  assert.throws(() => check(page(), page({ ...news, description: "Other." })), /same title as page-0\.html/);
  assert.throws(() => check(page(), page({ ...news, title: "Other" })), /same description as page-0\.html/);
  assert.throws(() => check(page(), page({ title: "Other", description: "Other." })), /same canonical link/);
  assert.doesNotThrow(() => check(page(), page({ ...news, title: "Other", description: "Other." })));
});

test("checkPages lists every problem at once", () => {
  const error = (() => {
    try {
      check("<html><head></head></html>");
    } catch (caught) {
      return caught;
    }
  })();
  assert.match(error.message, /<title>/);
  assert.match(error.message, /description/);
  assert.match(error.message, /og:image:alt/);
});

test("readHead copes with any attribute order and quoting", () => {
  const head = readHead(
    "<head><title>A &amp; B</title><meta content='Hello' name=description>" +
      '<meta content="Pic" property="og:image:alt"><link href="https://orielos.org/" rel="canonical"></head>',
  );
  assert.deepEqual(head.titles, ["A & B"]);
  assert.equal(head.meta.description, "Hello");
  assert.equal(head.meta["og:image:alt"], "Pic");
  assert.equal(head.canonical, "https://orielos.org/");
});

test("pageUrl serves index.html files by their folder", () => {
  assert.equal(pageUrl("index.html"), "https://orielos.org/");
  assert.equal(pageUrl("news/index.html"), "https://orielos.org/news/");
  assert.equal(pageUrl(String.raw`news\index.html`), "https://orielos.org/news/");
  assert.equal(pageUrl("press.html"), "https://orielos.org/press.html");
});

test("sitemapXml sorts and escapes the addresses", () => {
  const xml = sitemapXml(["https://orielos.org/news/", "https://orielos.org/", "https://orielos.org/?a=1&b=2"]);
  assert.match(xml, /^<\?xml version="1\.0" encoding="UTF-8"\?>\n<urlset xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9">/);
  const locs = [...xml.matchAll(/<loc>([^<]*)<\/loc>/g)].map((match) => match[1]);
  assert.deepEqual(locs, ["https://orielos.org/", "https://orielos.org/?a=1&amp;b=2", "https://orielos.org/news/"]);
});

test("robots.txt allows every crawler and names the sitemap", async () => {
  const robots = await readPublic("robots.txt");
  assert.match(robots, /^User-agent: \*$/m);
  assert.match(robots, /^Allow: \/$/m);
  assert.doesNotMatch(robots, /^Disallow:/m);
  assert.match(robots, /^Sitemap: https:\/\/orielos\.org\/sitemap\.xml$/m);
});
