// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Builds the orielos.org website into website/_site/.
//
// Usage: node website/build.mjs [--offline]
//
// Copies website/public/ and the shared artwork, then fills the contributors
// list and the latest release, with its installer ISO, into index.html from
// GitHub's REST API. Avatars are downloaded so visitors' browsers only contact
// our own domain. Pre-releases are left out: GitHub's "latest" is the newest
// full release. Finally it checks every page's title, description, canonical
// link and link preview for search engines, and writes the sitemap.

import { cp, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..");
const publicDir = path.join(here, "public");
const siteDir = path.join(here, "_site");
const artworkDir = path.join(repoRoot, "artwork");

export const SITE = "https://orielos.org";
const API = "https://api.github.com";
const MAX_PAGES = 5;
// Roughly what search results show before cutting the text off.
const MAX_TITLE = 70;
const MAX_DESCRIPTION = 160;
const AVATAR_CONCURRENCY = 8;
const FALLBACK_AVATAR = "favicon.svg";

const ARTWORK = [
  ["logo/orielos-logo.svg", "images/orielos-logo.svg"],
  ["logo/orielos-logo-dark.svg", "images/orielos-logo-dark.svg"],
  ["wallpapers/src/orielos-daybreak.svg", "images/daybreak.svg"],
  ["wallpapers/src/orielos-nightfall.svg", "images/nightfall.svg"],
  ["icons/orielos-start.svg", "favicon.svg"],
];

export function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

const ENTITIES = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'" };

export function decodeEntities(value) {
  return String(value).replace(/&(?:amp|lt|gt|quot|#39);/g, (entity) => ENTITIES[entity]);
}

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

export function sitemapXml(urls) {
  const entries = [...urls].sort().map((url) => `  <url><loc>${escapeHtml(url)}</loc></url>`);
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...entries,
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
  return { name, url, iso: isoFrom(json.assets) };
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

export function renderPage(template, { contributors, release }) {
  const iso = release?.iso ?? null;
  const flags = {
    release: Boolean(release),
    "no-release": !release,
    iso: Boolean(iso),
    "no-iso": !iso,
    sha256: Boolean(iso?.sha256),
    contributors: contributors.length > 0,
    "no-contributors": contributors.length === 0,
  };

  // Repeat until nothing changes, so blocks nested inside kept blocks resolve too.
  let html = template;
  for (let previous = ""; previous !== html; ) {
    previous = html;
    html = html.replace(
      /<!-- if:([a-z0-9-]+) -->([\s\S]*?)<!-- end:\1 -->/g,
      (_all, name, body) => {
        if (!(name in flags)) {
          throw new Error(`The page template has an unresolved marker: <!-- if:${name} -->`);
        }
        return flags[name] ? body : "";
      },
    );
  }

  const people = contributors
    .map(
      (person) =>
        `<li><a href="https://github.com/${encodeURIComponent(person.login)}">` +
        // The alt text differs from the name beside it, which Lighthouse would flag as redundant.
        `<img src="${escapeHtml(person.avatar)}" alt="${escapeHtml(person.login)}’s avatar" width="56" height="56" loading="lazy" decoding="async">` +
        `<span class="person-name">${escapeHtml(person.login)}</span></a></li>`,
    )
    .join("\n          ");
  html = html.replaceAll("<!-- contributors -->", () => people);

  if (release) {
    html = html
      .replaceAll("{{release.name}}", () => escapeHtml(release.name))
      .replaceAll("{{release.url}}", () => escapeHtml(release.url));
  }
  if (iso) {
    html = html
      .replaceAll("{{iso.url}}", () => escapeHtml(iso.url))
      .replaceAll("{{iso.size}}", () => escapeHtml(iso.size))
      .replaceAll("{{iso.sha256}}", () => escapeHtml(iso.sha256));
  }

  const leftover =
    /<!-- (?:if|end):[^>]*-->|<!-- contributors -->|\{\{(?:release|iso)\./.exec(html);
  if (leftover) {
    throw new Error(`The page template has an unresolved marker: ${leftover[0]}`);
  }
  return html;
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

async function fetchRelease(repo, token) {
  const url = `${API}/repos/${repo}/releases/latest`;
  const response = await apiGet(url, token);
  if (response.status === 404) return null;
  if (!response.ok) {
    throw new Error(`GitHub answered ${response.status} for ${url}.`);
  }
  return releaseFrom(await apiJson(response, url), repo);
}

async function downloadAvatar(person) {
  const url = `https://avatars.githubusercontent.com/u/${person.id}?s=112&v=4`;
  try {
    const response = await fetch(url, { headers: { "User-Agent": "orielos.org-build" } });
    if (!response.ok) throw new Error(`status ${response.status}`);
    const type = (response.headers.get("content-type") ?? "").split(";")[0].trim();
    const extension = { "image/png": "png", "image/jpeg": "jpg" }[type];
    if (!extension) throw new Error(`unsupported content type "${type}"`);
    const bytes = Buffer.from(await response.arrayBuffer());
    const relative = `avatars/${person.id}.${extension}`;
    await mkdir(path.join(siteDir, "avatars"), { recursive: true });
    await writeFile(path.join(siteDir, relative), bytes);
    return { login: person.login, avatar: relative };
  } catch (error) {
    console.warn(`Warning: no avatar for ${person.login}: ${error.message}`);
    return { login: person.login, avatar: FALLBACK_AVATAR };
  }
}

async function downloadAvatars(people) {
  const results = new Array(people.length);
  let next = 0;
  const worker = async () => {
    while (next < people.length) {
      const index = next;
      next += 1;
      results[index] = await downloadAvatar(people[index]);
    }
  };
  await Promise.all(
    Array.from({ length: Math.min(AVATAR_CONCURRENCY, people.length) }, worker),
  );
  return results;
}

async function build({ offline }) {
  const repo = process.env.GITHUB_REPOSITORY || "ncjsvr/OrielOS";
  const token = process.env.GITHUB_TOKEN || "";

  await rm(siteDir, { recursive: true, force: true });
  await cp(publicDir, siteDir, { recursive: true });
  for (const [from, to] of ARTWORK) {
    const target = path.join(siteDir, to);
    await mkdir(path.dirname(target), { recursive: true });
    await cp(path.join(artworkDir, from), target);
  }

  let contributors = [];
  let release = null;
  if (offline) {
    console.log("Offline: rendering with no contributors and no release.");
  } else {
    const people = await fetchContributors(repo, token);
    release = await fetchRelease(repo, token);
    contributors = await downloadAvatars(people);
  }

  const template = await readFile(path.join(publicDir, "index.html"), "utf8");
  await writeFile(
    path.join(siteDir, "index.html"),
    renderPage(template, { contributors, release }),
  );
  await writeFile(path.join(siteDir, ".nojekyll"), "");

  const pages = await indexablePages(siteDir);
  checkPages(pages);
  await writeFile(path.join(siteDir, "sitemap.xml"), sitemapXml(pages.map((page) => page.url)));

  console.log(
    `Built ${path.relative(process.cwd(), siteDir) || "."}: ` +
      `${contributors.length} contributor(s), ` +
      `${release ? `release ${release.name}` : "no release"}, ` +
      `${release?.iso ? `installer ${release.iso.size}` : "no installer"}, ` +
      `${pages.length} page(s) in the sitemap.`,
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  build({ offline: process.argv.includes("--offline") }).catch((error) => {
    console.error(`Website build failed: ${error.message}`);
    process.exit(1);
  });
}
