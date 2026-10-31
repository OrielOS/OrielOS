// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Builds the orielos.org website into website/_site/.
//
// Usage: node website/build.mjs [--offline]
//
// Copies website/public/ and the shared artwork, then builds every page: the
// home page and the not-found page from public/, the guides from docs/, the
// news posts from news/, the release notes from GitHub, and the pages in
// pages/, all with the header and footer in templates/. The contributors list
// and the latest release, with its installer ISO, come from GitHub's REST
// API. Avatars are downloaded so visitors' browsers only contact our own
// domain. The download is GitHub's "latest", the newest full (stable) release;
// pre-releases are the testing builds, shown in the release notes. Finally it
// checks every page's title, description, canonical link and link preview for
// search engines, and writes the sitemap.

import { execFileSync } from "node:child_process";
import { closeSync, existsSync, openSync, readSync } from "node:fs";
import { cp, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { decodeEntities, escapeHtml, imageDimensions, renderMarkdownDocument } from "./markdown.mjs";
import {
  SITE,
  applyIncludes,
  artworkCreditsHtml,
  atomFeed,
  contentPageContent,
  contentPageImage,
  contentPagesFrom,
  guideContent,
  guidesFrom,
  guidesIndexContent,
  newsIndexContent,
  postContent,
  postEntry,
  postHead,
  postHtml,
  postImage,
  postsFrom,
  latestTesting,
  releaseEntry,
  releaseHtml,
  releasesContent,
  releasesFrom,
  renderLayout,
  renderPage,
  stripLeadingComment,
  safeVersion,
  suffixedTitle,
} from "./pages.mjs";

export { SITE, decodeEntities, escapeHtml, renderPage };

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..");
const publicDir = path.join(here, "public");
const templatesDir = path.join(here, "templates");
const pagesDir = path.join(here, "pages");
const newsDir = path.join(here, "news");
const siteDir = path.join(here, "_site");
const artworkDir = path.join(repoRoot, "artwork");
const docsDir = path.join(repoRoot, "docs");

const API = "https://api.github.com";
const MAX_PAGES = 5;
// Roughly what search results show before cutting the text off.
const MAX_TITLE = 70;
const MAX_DESCRIPTION = 160;
const AVATAR_CONCURRENCY = 8;
const FALLBACK_AVATAR = "favicon.svg";
const RELEASES_SHOWN = 100;
// Sections in the site's main navigation that a page can belong to.
const NAV_SECTIONS = new Set(["download", "guides", "news"]);

const ARTWORK = [
  ["logo/orielos-logo.svg", "images/orielos-logo.svg"],
  ["logo/orielos-logo-dark.svg", "images/orielos-logo-dark.svg"],
  ["wallpapers/src/orielos-daybreak.svg", "images/daybreak.svg"],
  ["wallpapers/src/orielos-nightfall.svg", "images/nightfall.svg"],
  ["icons/orielos-start.svg", "favicon.svg"],
];

// A tag's attributes, whatever their order or quoting.
function attributesOf(tag) {
  const attributes = {};
  for (const match of tag.matchAll(/([a-zA-Z][\w:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/g)) {
    attributes[match[1].toLowerCase()] = decodeEntities(match[2] ?? match[3] ?? match[4]);
  }
  return attributes;
}

// What search engines and link previews read from a page: its titles, the
// meta tags by name or property (the first of each), the canonical link,
// every script block and every image.
export function readHead(html) {
  const head = /<head\b[^>]*>([\s\S]*?)<\/head>/i.exec(html)?.[1] ?? "";
  const titles = [...head.matchAll(/<title\b[^>]*>([\s\S]*?)<\/title>/gi)].map((match) =>
    decodeEntities(match[1].trim()),
  );
  const meta = {};
  for (const [tag] of head.matchAll(/<meta\b[^>]*>/gi)) {
    const attributes = attributesOf(tag);
    const key = (attributes.property ?? attributes.name ?? "").toLowerCase();
    if (key !== "" && attributes.content !== undefined && !(key in meta)) {
      meta[key] = attributes.content;
    }
  }
  let canonical = null;
  for (const [tag] of head.matchAll(/<link\b[^>]*>/gi)) {
    const attributes = attributesOf(tag);
    if ((attributes.rel ?? "").toLowerCase().split(/\s+/).includes("canonical")) {
      canonical = attributes.href ?? "";
    }
  }
  const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\b[^>]*>/gi)].map((match) => ({
    type: (attributesOf(match[1]).type ?? "").toLowerCase(),
    body: match[2],
  }));
  // A script tag that is never closed still counts, so it can't slip past the checks.
  if ((html.match(/<script\b/gi)?.length ?? 0) > scripts.length) {
    scripts.push({ type: "unclosed", body: "" });
  }
  const images = [...html.matchAll(/<img\b[^>]*>/gi)].map(([tag]) => attributesOf(tag));
  return { titles, meta, canonical, scripts, images };
}

export function isNoindex(html) {
  return /\bnoindex\b/i.test(readHead(html).meta.robots ?? "");
}

// The address a built file is served at: index.html files by their folder.
export function pageUrl(relativePath) {
  const file = relativePath.replaceAll("\\", "/");
  if (file === "index.html") return `${SITE}/`;
  if (file.endsWith("/index.html")) return `${SITE}/${encodeURI(file.slice(0, -"index.html".length))}`;
  return `${SITE}/${encodeURI(file)}`;
}

// Throws one error listing every problem, so a broken page never goes live.
// pages: [{ file, url, html }] for every page that search engines may index.
export function checkPages(pages) {
  const problems = [];
  const seen = { title: new Map(), description: new Map(), "canonical link": new Map() };
  for (const { file, url, html } of pages) {
    const problem = (message) => problems.push(`${file}: ${message}`);
    const { titles, meta, canonical, scripts, images } = readHead(html);

    const title = titles[0] ?? "";
    if (titles.length !== 1 || title === "") {
      problem("needs exactly one <title>, with text.");
    } else if (title.length > MAX_TITLE) {
      problem(`the title has ${title.length} characters; keep it to ${MAX_TITLE}.`);
    }
    const description = meta.description ?? "";
    if (description === "") {
      problem('needs a <meta name="description">.');
    } else if (description.length > MAX_DESCRIPTION) {
      problem(`the description has ${description.length} characters; keep it to ${MAX_DESCRIPTION}.`);
    }
    if (canonical !== url) problem(`the canonical link should be ${url}.`);
    for (const name of ["og:title", "og:description", "og:image", "og:image:alt"]) {
      if (!meta[name]) problem(`needs ${name}.`);
    }
    if (meta["og:url"] !== url) problem(`og:url should be ${url}.`);
    if (meta["og:image"] && !meta["og:image"].startsWith(`${SITE}/`)) {
      problem(`og:image should be on ${SITE}.`);
    }
    if (meta["twitter:site"] !== "@BuiltByNath") problem("needs twitter:site set to @BuiltByNath.");
    // Search engines read alt text, and SEO checkers flag empty alt, so even
    // images in parts hidden from screen readers get some.
    for (const image of images) {
      if (!image.alt?.trim()) problem(`an <img> has no alt text: ${image.src ?? "(no src)"}.`);
    }
    for (const script of scripts) {
      if (script.type !== "application/ld+json") {
        problem("has a <script> that browsers would run; the site has no JavaScript.");
        continue;
      }
      try {
        JSON.parse(script.body);
      } catch (error) {
        problem(`has structured data that isn't valid JSON (${error.message}).`);
      }
    }
    for (const [kind, value] of [["title", title], ["description", description], ["canonical link", canonical]]) {
      if (!value) continue;
      const other = seen[kind].get(value);
      if (other) problem(`has the same ${kind} as ${other}.`);
      else seen[kind].set(value, file);
    }
  }
  if (problems.length > 0) {
    throw new Error(`Some pages aren't ready for search engines:\n  ${problems.join("\n  ")}`);
  }
}

// "2026-10-27" dates from `git log --format=%cs --name-only`, newest commit
// first. The first date seen for a file is the one kept.
export function datesFromGitLog(output) {
  const dates = new Map();
  let date = null;
  for (const line of String(output).replace(/\r\n?/g, "\n").split("\n")) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(line)) date = line;
    else if (line !== "" && date !== null && !dates.has(line)) dates.set(line, date);
  }
  return dates;
}

export function newestDate(dates) {
  let newest = null;
  for (const date of dates) {
    if (typeof date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(date) && (newest === null || date > newest)) {
      newest = date;
    }
  }
  return newest;
}

function runGit(args, cwd) {
  return execFileSync("git", args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    timeout: 15000,
  });
}

// The commit date of each file git can see, as YYYY-MM-DD. Files git can't
// date, and a checkout with no history for them, are left out: a shallow
// clone often can't see the commit that last changed a file, and guessing
// from the checkout time would tell search engines every page changed today.
export function gitLastModified(files, { root = repoRoot, run = runGit } = {}) {
  const paths = [
    ...new Set(
      files.filter((file) => typeof file === "string" && file !== "" && !file.startsWith("-") && !file.includes("\0")),
    ),
  ];
  if (paths.length === 0) return new Map();
  let output = "";
  try {
    output = run(["log", "--format=%cs", "--name-only", "--", ...paths], root);
  } catch {
    return new Map();
  }
  const dates = datesFromGitLog(output);
  const wanted = new Set(paths);
  for (const file of [...dates.keys()]) {
    if (!wanted.has(file)) dates.delete(file);
  }
  return dates;
}

// entries: page addresses, or { url, lastmod } when the build could date the
// page. lastmod is a YYYY-MM-DD date, or it is left out.
export function sitemapXml(entries) {
  const items = entries.map((entry) => (typeof entry === "string" ? { url: entry } : entry));
  const rows = items
    .slice()
    .sort((a, b) => (a.url < b.url ? -1 : a.url > b.url ? 1 : 0))
    .map((entry) => {
      const lastmod =
        typeof entry.lastmod === "string" && /^\d{4}-\d{2}-\d{2}$/.test(entry.lastmod)
          ? `<lastmod>${escapeHtml(entry.lastmod)}</lastmod>`
          : "";
      return `  <url><loc>${escapeHtml(entry.url)}</loc>${lastmod}</url>`;
    });
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...rows,
    "</urlset>",
    "",
  ].join("\n");
}

// Every built page that search engines may index, with its address.
async function indexablePages(dir) {
  const files = (await readdir(dir, { recursive: true }))
    .filter((file) => file.endsWith(".html"))
    .map((file) => file.replaceAll("\\", "/"))
    .sort();
  const pages = [];
  for (const file of files) {
    const html = await readFile(path.join(dir, file), "utf8");
    if (!isNoindex(html)) pages.push({ file, url: pageUrl(file), html });
  }
  return pages;
}

export function isHuman(entry) {
  return (
    entry !== null &&
    typeof entry === "object" &&
    Number.isInteger(entry.id) &&
    typeof entry.login === "string" &&
    entry.login !== "" &&
    entry.type !== "Bot" &&
    !entry.login.endsWith("[bot]")
  );
}

export function releaseFrom(json, repo) {
  const fallbackUrl = `https://github.com/${repo}/releases/latest`;
  const name = [json?.name, json?.tag_name].find(
    (value) => typeof value === "string" && value !== "",
  );
  if (name === undefined) {
    throw new Error("The latest release has neither a name nor a tag.");
  }
  const url = isGitHubUrl(json.html_url) ? json.html_url : fallbackUrl;
  const tag = typeof json?.tag_name === "string" ? json.tag_name.trim() : "";
  return { name, version: safeVersion(tag), url, iso: isoFrom(json.assets) };
}

function isGitHubUrl(value) {
  return typeof value === "string" && value.startsWith("https://github.com/");
}

// The release's installer: the first uploaded .iso asset, linked directly.
export function isoFrom(assets) {
  if (!Array.isArray(assets)) return null;
  const asset = assets.find(
    (item) =>
      typeof item?.name === "string" &&
      item.name.toLowerCase().endsWith(".iso") &&
      (item.state === undefined || item.state === "uploaded") &&
      isGitHubUrl(item.browser_download_url) &&
      Number.isInteger(item.size),
  );
  if (!asset) return null;
  const digest = typeof asset.digest === "string" ? asset.digest : "";
  const sha256 = /^sha256:[0-9a-f]{64}$/.test(digest) ? digest.slice("sha256:".length) : "";
  return { url: asset.browser_download_url, size: formatSize(asset.size), sha256 };
}

// The release's checksum file: an uploaded asset named exactly SHA256SUMS.
export function sumsFrom(assets) {
  if (!Array.isArray(assets)) return null;
  const asset = assets.find(
    (item) =>
      item?.name === "SHA256SUMS" &&
      (item.state === undefined || item.state === "uploaded") &&
      isGitHubUrl(item.browser_download_url),
  );
  return asset ? { url: asset.browser_download_url } : null;
}

export function formatSize(bytes) {
  // A non-breaking space keeps the number and its unit together.
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`;
  return `${Math.max(1, Math.round(bytes / 1e6))} MB`;
}

export function nextLink(header) {
  if (!header) return null;
  for (const part of header.split(",")) {
    const match = /^\s*<([^>]*)>\s*;(.*)$/.exec(part);
    if (match && /;?\s*rel="?next"?\s*(;|$)/.test(`;${match[2]}`)) {
      return match[1];
    }
  }
  return null;
}

function githubHeaders(token) {
  const headers = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "orielos.org-build",
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

async function apiGet(url, token) {
  let response;
  try {
    response = await fetch(url, { headers: githubHeaders(token) });
  } catch (error) {
    throw new Error(`Could not reach ${url}: ${error.message}`);
  }
  return response;
}

async function apiJson(response, url) {
  try {
    return await response.json();
  } catch {
    throw new Error(`GitHub returned invalid JSON for ${url}.`);
  }
}

async function fetchContributors(repo, token) {
  const all = [];
  let url = `${API}/repos/${repo}/contributors?per_page=100`;
  for (let page = 0; url && page < MAX_PAGES; page += 1) {
    const response = await apiGet(url, token);
    if (response.status === 204) break;
    if (!response.ok) {
      throw new Error(`GitHub answered ${response.status} for ${url}.`);
    }
    const json = await apiJson(response, url);
    if (!Array.isArray(json)) {
      throw new Error(`GitHub returned an unexpected response for ${url}.`);
    }
    all.push(...json.filter(isHuman));
    url = nextLink(response.headers.get("link"));
  }
  return all.map(({ id, login }) => ({ id, login }));
}

// GitHub's latest full release, as it returns it, or null if there is none.
async function fetchLatestRelease(repo, token) {
  const url = `${API}/repos/${repo}/releases/latest`;
  const response = await apiGet(url, token);
  if (response.status === 404) return null;
  if (!response.ok) {
    throw new Error(`GitHub answered ${response.status} for ${url}.`);
  }
  return apiJson(response, url);
}

// The newest releases, for the release notes and the feed.
async function fetchReleases(repo, token) {
  const url = `${API}/repos/${repo}/releases?per_page=${RELEASES_SHOWN}`;
  const response = await apiGet(url, token);
  if (response.status === 404) return [];
  if (!response.ok) {
    throw new Error(`GitHub answered ${response.status} for ${url}.`);
  }
  const json = await apiJson(response, url);
  if (!Array.isArray(json)) {
    throw new Error(`GitHub returned an unexpected response for ${url}.`);
  }
  return json;
}

async function downloadAvatar(person, outDir) {
  const url = `https://avatars.githubusercontent.com/u/${person.id}?s=112&v=4`;
  try {
    const response = await fetch(url, { headers: { "User-Agent": "orielos.org-build" } });
    if (!response.ok) throw new Error(`status ${response.status}`);
    const type = (response.headers.get("content-type") ?? "").split(";")[0].trim();
    const extension = { "image/png": "png", "image/jpeg": "jpg" }[type];
    if (!extension) throw new Error(`unsupported content type "${type}"`);
    const bytes = Buffer.from(await response.arrayBuffer());
    const relative = `avatars/${person.id}.${extension}`;
    await mkdir(path.join(outDir, "avatars"), { recursive: true });
    await writeFile(path.join(outDir, relative), bytes);
    return { login: person.login, avatar: relative };
  } catch (error) {
    console.warn(`Warning: no avatar for ${person.login}: ${error.message}`);
    return { login: person.login, avatar: FALLBACK_AVATAR };
  }
}

async function downloadAvatars(people, outDir) {
  const results = new Array(people.length);
  let next = 0;
  const worker = async () => {
    while (next < people.length) {
      const index = next;
      next += 1;
      results[index] = await downloadAvatar(people[index], outDir);
    }
  };
  await Promise.all(
    Array.from({ length: Math.min(AVATAR_CONCURRENCY, people.length) }, worker),
  );
  return results;
}

// Every file in a folder with the given extensions, with its text; none if
// the folder doesn't exist.
async function readSources(dir, extensions) {
  if (!existsSync(dir)) return [];
  const files = (await readdir(dir, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && extensions.some((extension) => entry.name.endsWith(extension)))
    .map((entry) => entry.name)
    .sort();
  return Promise.all(files.map(async (file) => ({ file, source: await readFile(path.join(dir, file), "utf8") })));
}

// The header and footer, without their SPDX comments.
export async function loadPartials(dir = templatesDir) {
  const partials = {};
  for (const name of ["header", "footer"]) {
    partials[name] = stripLeadingComment(await readFile(path.join(dir, `${name}.html`), "utf8"));
  }
  return partials;
}

// The pixel size of a PNG or WebP image on the built site, read from its
// header; null if it can't be read.
function imageSizer(outDir) {
  return (src) => {
    if (!src.startsWith("/") || src.startsWith("//")) return null;
    const file = path.join(outDir, ...decodeURI(src.split(/[?#]/)[0]).split("/").filter(Boolean));
    if (!file.startsWith(outDir) || !/\.(png|webp)$/i.test(file)) return null;
    let handle;
    try {
      handle = openSync(file, "r");
      const bytes = Buffer.alloc(32);
      const read = readSync(handle, bytes, 0, 32, 0);
      return imageDimensions(bytes.subarray(0, read));
    } catch {
      return null;
    } finally {
      if (handle !== undefined) closeSync(handle);
    }
  };
}

export async function build({ offline = false, outDir = siteDir } = {}) {
  const repo = process.env.GITHUB_REPOSITORY || "OrielOS/OrielOS";
  const token = process.env.GITHUB_TOKEN || "";

  await rm(outDir, { recursive: true, force: true });
  await cp(publicDir, outDir, { recursive: true });
  for (const [from, to] of ARTWORK) {
    const target = path.join(outDir, to);
    await mkdir(path.dirname(target), { recursive: true });
    await cp(path.join(artworkDir, from), target);
  }
  if (existsSync(path.join(docsDir, "images"))) {
    await cp(path.join(docsDir, "images"), path.join(outDir, "guides", "images"), { recursive: true });
  }

  let contributors = [];
  let release = null;
  let sums = null;
  let releases = [];
  if (offline) {
    console.log("Offline: rendering with no contributors and no releases.");
  } else {
    const people = await fetchContributors(repo, token);
    const latest = await fetchLatestRelease(repo, token);
    if (latest) {
      release = releaseFrom(latest, repo);
      sums = sumsFrom(latest.assets);
    }
    releases = releasesFrom(await fetchReleases(repo, token), repo);
    contributors = await downloadAvatars(people, outDir);
  }

  const partials = await loadPartials();
  const layout = await readFile(path.join(templatesDir, "page.html"), "utf8");
  const imageSize = imageSizer(outDir);
  // Where each built page's words come from, so the sitemap can date it.
  // Shared templates are included: a change to the header or footer changes
  // every page that uses them.
  const sources = new Map();
  const extraDates = new Map();
  const layoutSources = [
    "website/templates/page.html",
    "website/templates/header.html",
    "website/templates/footer.html",
  ];
  const note = (relative, files, extra = null) => {
    sources.set(relative, files);
    if (extra) extraDates.set(relative, extra);
  };
  const write = async (relative, content) => {
    const target = path.join(outDir, relative);
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, content);
  };
  const page = (relative, details) => write(relative, renderLayout(layout, partials, { ...details, url: pageUrl(relative) }));
  const requireImage = (file, image) => {
    if (image && !existsSync(path.join(outDir, ...image.path.split("/").filter(Boolean)))) {
      throw new Error(`${file}: the image ${image.path} isn't in website/public/ or the shared artwork.`);
    }
  };

  // Guides, from docs/.
  const docs = await readSources(docsDir, [".md"]);
  const readme = docs.find(({ file }) => file === "README.md")?.source ?? "";
  const groups = guidesFrom(docs, readme, { imageSize });
  const guides = groups.flatMap((group) => group.guides);
  for (const [index, guide] of guides.entries()) {
    note(`guides/${guide.slug}/index.html`, [`docs/${guide.file}`, ...layoutSources]);
    await page(`guides/${guide.slug}/index.html`, {
      title: guide.title,
      ogTitle: guide.heading,
      description: guide.description,
      current: "guides",
      content: guideContent(guide, guides[index - 1], guides[index + 1]),
    });
  }
  note("guides/index.html", [...docs.map(({ file }) => `docs/${file}`), ...layoutSources]);
  await page("guides/index.html", {
    title: "Guides to installing and using OrielOS",
    description:
      "How to install OrielOS, use the desktop, Start, Settings and the Store, keep it updated and set it up for games, with an A to Z of every topic.",
    current: "guides",
    content: guidesIndexContent(groups),
  });

  // News, from news/, and the feed.
  const posts = postsFrom(await readSources(newsDir, [".md"]));
  for (const post of posts) {
    requireImage(post.file, post.image);
    note(`news/${post.slug}/index.html`, [post.file, ...layoutSources]);
    await page(`news/${post.slug}/index.html`, {
      title: suffixedTitle(post.title, "OrielOS news"),
      ogTitle: post.title,
      description: post.summary,
      current: "news",
      ogType: "article",
      image: postImage(post) ?? undefined,
      head: postHead(post),
      content: postContent(post, postHtml(post, { imageSize })),
    });
  }
  note("news/index.html", [...posts.map((post) => post.file), ...layoutSources]);
  await page("news/index.html", {
    title: "OrielOS news",
    description: "News from the OrielOS project: releases, milestones and what's coming next, newest first, with a feed to follow.",
    current: "news",
    content: newsIndexContent(posts),
  });
  const entries = [
    ...posts.map((post) => postEntry(post, postHtml(post, { forFeed: true, imageSize }))),
    // Testing builds come often, so the feed follows stable versions only.
    ...releases.filter((item) => !item.testing).map((item) => releaseEntry(item, releaseHtml(item))),
  ];
  await write("news/feed.xml", atomFeed(entries));

  // Release notes. The page is filled from GitHub, so its date is also the
  // newest release's publish date when that is later than the changelog.
  note("releases/index.html", ["CHANGELOG.md", ...layoutSources], releases[0]?.publishedAt?.slice(0, 10) ?? null);
  await page("releases/index.html", {
    title: "Release notes · OrielOS",
    description: "What changed in each OrielOS version, newest first: every testing build and every stable version, with links to them and the installer on GitHub.",
    content: releasesContent(releases),
  });

  // Pages from pages/.
  const data = { contributors, release, sums, news: posts, testing: latestTesting(releases) };
  const artworkCredits = artworkCreditsHtml(await readFile(path.join(artworkDir, "CREDITS.md"), "utf8"));
  const contentPages = contentPagesFrom(await readSources(pagesDir, [".html", ".md"]));
  for (const item of contentPages) {
    requireImage(item.file, item.image);
    let body;
    try {
      body =
        item.kind === "html"
          ? renderPage(item.body, { ...data, artworkCredits })
          : renderMarkdownDocument(item.body, { imageSize }).html;
    } catch (error) {
      throw new Error(`${item.file}: ${error.message}`);
    }
    note(`${item.slug}/index.html`, [item.file, ...layoutSources]);
    await page(`${item.slug}/index.html`, {
      title: item.title,
      ogTitle: item.heading,
      description: item.description,
      current: NAV_SECTIONS.has(item.slug) ? item.slug : "",
      image: contentPageImage(item) ?? undefined,
      content: contentPageContent(item, body),
    });
  }

  // The home page and the not-found page. The home page has its own document,
  // so it doesn't use the shared page template.
  const home = await readFile(path.join(publicDir, "index.html"), "utf8");
  note("index.html", ["website/public/index.html", "website/templates/header.html", "website/templates/footer.html"]);
  await write("index.html", renderPage(applyIncludes(home, partials), data));
  const notFound = await readFile(path.join(publicDir, "404.html"), "utf8");
  await write("404.html", renderPage(applyIncludes(notFound, partials)));
  await write(".nojekyll", "");

  const pages = await indexablePages(outDir);
  checkPages(pages);
  const sourceDates = gitLastModified([...sources.values()].flat());
  const dated = pages.map((item) => ({
    url: item.url,
    lastmod: newestDate([
      ...(sources.get(item.file) ?? []).map((file) => sourceDates.get(file)),
      extraDates.get(item.file),
    ]),
  }));
  await write("sitemap.xml", sitemapXml(dated));

  console.log(
    `Built ${path.relative(process.cwd(), outDir) || "."}: ` +
      `${contributors.length} contributor(s), ` +
      `${release ? `release ${release.name}` : "no release"}, ` +
      `${release?.iso ? `installer ${release.iso.size}` : "no installer"}, ` +
      `${guides.length} guide(s), ${posts.length} news post(s), ${releases.length} release note(s), ` +
      `${pages.length} page(s) in the sitemap.`,
  );
  return { pages: pages.map((item) => item.file) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  build({ offline: process.argv.includes("--offline") }).catch((error) => {
    console.error(`Website build failed: ${error.message}`);
    process.exit(1);
  });
}
