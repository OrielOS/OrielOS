// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The pages of orielos.org other than the checks and GitHub's API: the shared
// layout, the guides from docs/, the news posts and their feed, the release
// notes, and the pages in website/pages/. Everything here is a pure function
// of its inputs, so the tests can call it directly; build.mjs reads the files
// and writes the results.

import path from "node:path";

import { escapeHtml, renderMarkdownDocument, renderMarkdownInline, slugify } from "./markdown.mjs";

export const SITE = "https://orielos.org";
export const REPO_URL = "https://github.com/OrielOS/OrielOS";
const BLOB = `${REPO_URL}/blob/main/`;
const DISCUSSIONS_QA = `${REPO_URL}/discussions/categories/q-a`;
const DISCORD = "https://discord.gg/RnpZYaKbHA";
const MAX_TITLE = 70;
const MAX_DESCRIPTION = 155;
const MAX_SUMMARY = 160;
const HOME_NEWS = 3;

export const DEFAULT_IMAGE = {
  url: `${SITE}/images/open-graph.png`,
  alt: "The OrielOS logo and wordmark beside a glowing bay window of three glass panes, on deep blue",
  width: 1200,
  height: 630,
};

// The guides index, in reading order. A guide not listed here goes into "More".
export const GUIDE_GROUPS = [
  { title: "Get started", slugs: ["install", "install-vm", "status", "known-limitations"] },
  { title: "Everyday use", slugs: ["desktop", "start-menu", "keyboard-shortcuts", "settings", "apps", "windows-programs", "updates", "help"] },
  { title: "Gaming", slugs: ["games-and-controllers", "anti-cheat", "secure-boot"] },
];

// Addresses that the generated pages use, so content pages can't take them.
const RESERVED = new Set(["guides", "news", "releases", "images", "fonts", "avatars", "index", "404"]);

// JSON for a <script type="application/ld+json"> block: "<" is escaped so the
// text can never close the script element.
export function jsonLd(data) {
  return `<script type="application/ld+json">\n${JSON.stringify(data, null, 2).replaceAll("<", "\\u003c")}\n</script>`;
}

const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

export function isDate(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().startsWith(value);
}

// "2026-10-27" as "27 October 2026".
export function formatDate(value) {
  const [year, month, day] = value.slice(0, 10).split("-").map(Number);
  return `${day} ${MONTHS[month - 1]} ${year}`;
}

// Text cut at a word boundary so it is at most `max` characters, with "…" if cut.
export function truncate(text, max = MAX_DESCRIPTION) {
  const clean = String(text).replace(/\s+/g, " ").trim();
  if (clean.length <= max) return clean;
  const cut = clean.slice(0, max);
  const space = cut.lastIndexOf(" ");
  return `${(space > max / 2 ? cut.slice(0, space) : cut).replace(/[\s,;:.–—-]+$/, "")}…`;
}

// ---------------------------------------------------------------------------
// Front matter

// Splits "---" front matter of simple "key: value" lines from the body.
export function parseFrontMatter(source, file = "the file") {
  const text = String(source).replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n");
  if (!text.startsWith("---\n")) {
    throw new Error(`${file}: needs front matter between "---" lines at the top.`);
  }
  const end = text.indexOf("\n---", 3);
  if (end === -1 || !/^\n---[ \t]*(\n|$)/.test(text.slice(end))) {
    throw new Error(`${file}: the front matter has no closing "---" line.`);
  }
  const data = {};
  const lines = text.slice(4, end).split("\n");
  for (const [index, line] of lines.entries()) {
    if (/^\s*(#.*)?$/.test(line)) continue;
    const match = /^([A-Za-z][\w-]*)\s*:\s*(.*?)\s*$/.exec(line);
    if (!match) {
      throw new Error(`${file}: front matter line ${index + 2} isn't "key: value": ${line}`);
    }
    let value = match[2];
    if (/^(["']).*\1$/.test(value) && value.length >= 2) value = value.slice(1, -1);
    if (match[1] in data) throw new Error(`${file}: the front matter sets "${match[1]}" twice.`);
    data[match[1]] = value;
  }
  const body = text.slice(end + 4).replace(/^[ \t]*\n/, "");
  return { data, body };
}

// An image path under website/public/, such as /images/news/x.png.
function isSitePath(value) {
  return /^\/[^/\\]/.test(value) && !value.split("/").includes("..") && !/[\s"'<>]/.test(value);
}

function checkImage(data, problems) {
  if (data.image === undefined || data.image === "") {
    for (const key of ["image_alt", "image_width", "image_height"]) {
      if (data[key] !== undefined) problems.push(`"${key}" needs an "image".`);
    }
    return null;
  }
  if (!isSitePath(data.image)) problems.push(`"image" should be a path on the site, such as /images/news/picture.png.`);
  if (!data.image_alt) problems.push(`"image" needs "image_alt", a description of the picture.`);
  const size = {};
  for (const key of ["image_width", "image_height"]) {
    if (data[key] === undefined) continue;
    if (!/^[1-9]\d{0,4}$/.test(data[key])) problems.push(`"${key}" should be a whole number of pixels.`);
    else size[key.slice("image_".length)] = Number(data[key]);
  }
  return { path: data.image, alt: data.image_alt ?? "", width: size.width ?? null, height: size.height ?? null };
}

function fail(file, problems) {
  if (problems.length > 0) throw new Error(`${file}: ${problems.join(" ")}`);
}

const slugOf = (file) => path.basename(file).replace(/\.(md|html)$/, "");

// ---------------------------------------------------------------------------
// Layout

// Replaces <!-- include:name --> with a partial, marking the nav link of the
// current section with aria-current.
export function applyIncludes(html, partials, { current = "" } = {}) {
  return html.replace(/<!-- include:([a-z0-9-]+) -->/g, (marker, name) => {
    if (!(name in partials)) throw new Error(`Unknown include: ${marker}`);
    return partials[name].replace(/\{\{nav\.([a-z0-9-]+)\}\}/g, (_all, key) =>
      key === current ? ' aria-current="page"' : "",
    );
  });
}

// Partials and templates start with an SPDX comment that pages don't need.
export function stripLeadingComment(text) {
  return String(text).replace(/^\s*<!--[\s\S]*?-->\s*/, "").trimEnd();
}

// A release tag safe to drop into HTML and into JSON-LD, such as v0.0.7.
export function safeVersion(value) {
  return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(value) ? value : "";
}

// Fills page.html: {{title}}, {{description}}, {{url}}, {{og.type}},
// {{og.title}}, {{image.url}}, {{image.alt}}, {{image.width}} and
// {{image.height}} with escaped text, and <!-- head --> and <!-- content -->
// with HTML. It runs once over the layout, so nothing inside the content is
// ever read as a placeholder. Width and height are left out when the picture
// has no size, rather than published empty.
export function renderLayout(layout, partials, page) {
  const image = page.image ?? DEFAULT_IMAGE;
  const hasSize = Boolean(image.width && image.height);
  const values = {
    title: page.title,
    description: page.description,
    url: page.url,
    "og.type": page.ogType ?? "website",
    "og.title": page.ogTitle ?? page.title,
    "image.url": image.url,
    "image.alt": image.alt,
    "image.width": hasSize ? String(image.width) : "",
    "image.height": hasSize ? String(image.height) : "",
  };
  const head = (page.head ?? "").trimEnd();
  let html = applyIncludes(layout, partials, { current: page.current ?? "" }).replace(
    /\{\{([a-z.]+)\}\}|<!-- (head|content) -->/g,
    (marker, key, slot) => {
      if (slot === "head") return head;
      if (slot === "content") return page.content;
      if (!(key in values) || values[key] === undefined) throw new Error(`The page layout has an unknown placeholder: ${marker}`);
      return escapeHtml(values[key]);
    },
  );
  if (!hasSize) {
    html = html.replace(
      /\n<meta property="og:image:width" content="">\n<meta property="og:image:height" content="">/,
      "",
    );
  }
  return html;
}

// "<name> · OrielOS guides", or just the name if that would be too long.
export function suffixedTitle(name, suffix) {
  const full = `${name} · ${suffix}`;
  return full.length <= MAX_TITLE ? full : name;
}

// ---------------------------------------------------------------------------
// The home page's and the content pages' blocks and placeholders

function newsItems(posts, heading) {
  return posts
    .map(
      (post) =>
        `<li><article>` +
        `<${heading} class="news-title"><a href="/news/${post.slug}/">${escapeHtml(post.title)}</a></${heading}>` +
        `<p class="news-date"><time datetime="${post.date}">${formatDate(post.date)}</time></p>` +
        `<p class="news-summary">${escapeHtml(post.summary)}</p>` +
        `</article></li>`,
    )
    .join("\n      ");
}

// Fills a page template: keeps or removes the <!-- if:name --> blocks and
// fills the {{release.*}}, {{iso.*}}, {{sums.*}} and {{testing.*}} placeholders and the
// <!-- contributors -->, <!-- news --> and <!-- artwork-credits --> markers.
export function renderPage(template, { contributors = [], release = null, sums = null, news = [], artworkCredits = null, testing = null } = {}) {
  const iso = release?.iso ?? null;
  const version = safeVersion(release?.version);
  const testingVersion = safeVersion(testing?.version);
  const flags = {
    release: Boolean(release),
    "no-release": !release,
    testing: testingVersion !== "",
    "no-testing": testingVersion === "",
    version: version !== "",
    "no-version": version === "",
    iso: Boolean(iso),
    "no-iso": !iso,
    sha256: Boolean(iso?.sha256),
    "no-sha256": !iso?.sha256,
    sums: Boolean(sums),
    "no-sums": !sums,
    contributors: contributors.length > 0,
    "no-contributors": contributors.length === 0,
    news: news.length > 0,
    "no-news": news.length === 0,
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
  html = html.replaceAll("<!-- news -->", () => newsItems(news.slice(0, HOME_NEWS), "h3"));
  if (artworkCredits !== null) html = html.replaceAll("<!-- artwork-credits -->", () => artworkCredits);

  if (release) {
    html = html
      .replaceAll("{{release.name}}", () => escapeHtml(release.name))
      .replaceAll("{{release.url}}", () => escapeHtml(release.url));
    if (version) html = html.replaceAll("{{release.version}}", () => escapeHtml(version));
  }
  if (iso) {
    html = html
      .replaceAll("{{iso.url}}", () => escapeHtml(iso.url))
      .replaceAll("{{iso.size}}", () => escapeHtml(iso.size))
      .replaceAll("{{iso.sha256}}", () => escapeHtml(iso.sha256));
  }
  if (sums) html = html.replaceAll("{{sums.url}}", () => escapeHtml(sums.url));
  if (testingVersion) {
    html = html
      .replaceAll("{{testing.version}}", () => escapeHtml(testingVersion))
      .replaceAll("{{testing.url}}", () => escapeHtml(`/releases/#${encodeURIComponent(testingVersion)}`));
  }

  const leftover =
    /<!-- (?:if|end|include):[^>]*-->|<!-- (?:contributors|news|artwork-credits) -->|\{\{(?:release|iso|sums|testing)\./.exec(html);
  if (leftover) {
    throw new Error(`The page template has an unresolved marker: ${leftover[0]}`);
  }
  return html;
}

// ---------------------------------------------------------------------------
// Guides

// Where a link in docs/ should go on the site: other guides to their pages,
// the docs README to the guides index, and other files to GitHub.
export function guideLink(href, slugs) {
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(href) || href.startsWith("#") || href.startsWith("/")) return href;
  const hashAt = href.indexOf("#");
  const target = hashAt === -1 ? href : href.slice(0, hashAt);
  const hash = hashAt === -1 ? "" : href.slice(hashAt);
  if (target === "") return href;
  const resolved = path.posix.normalize(path.posix.join("docs", target));
  if (resolved.startsWith("..")) return REPO_URL;
  if (resolved === "docs/README.md" || resolved === "docs" || resolved === "docs/") return `/guides/${hash}`;
  const guide = /^docs\/([^/]+)\.md$/.exec(resolved);
  if (guide && slugs.has(guide[1])) return `/guides/${guide[1]}/${hash}`;
  return `${BLOB}${resolved}${hash}`;
}

// Images in docs/ are served from /guides/images/.
export function guideImage(src) {
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(src) || src.startsWith("/") || src.startsWith("#")) return src;
  const resolved = path.posix.normalize(path.posix.join("docs", src));
  if (!resolved.startsWith("docs/images/")) return guideLink(src, new Set());
  return `/guides/images/${resolved.slice("docs/images/".length)}`;
}

// A link in a release's notes or the CHANGELOG: relative paths go to GitHub.
export function repoLink(href, base = "") {
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(href) || href.startsWith("#") || href.startsWith("/")) return href;
  const resolved = path.posix.normalize(path.posix.join(base || ".", href));
  if (resolved.startsWith("..")) return REPO_URL;
  return `${BLOB}${resolved === "." ? "" : resolved}`;
}

// The docs README's one-line descriptions: "- [Title](file.md): blurb".
export function guideBlurbs(readme) {
  const blurbs = new Map();
  for (const line of String(readme).split(/\r?\n/)) {
    const match = /^\s*[-*]\s+\[[^\]]*\]\(([^)#\s]+)\.md\)\s*:\s*(.+?)\s*$/.exec(line);
    if (match) blurbs.set(path.posix.basename(match[1]), match[2]);
  }
  return blurbs;
}

// The "Licence: ..." line that ends a doc on GitHub; the site says it in the page's footer.
function withoutLicenceLine(source) {
  const lines = String(source).replace(/\r\n?/g, "\n").trimEnd().split("\n");
  if (/^Licence: CC BY-SA 4\.0\b/.test(lines.at(-1) ?? "")) lines.pop();
  return lines.join("\n").trimEnd() + "\n";
}

// One guide from docs/<file>.md: its address, titles, description and HTML.
// options.imageSize is passed to the renderer for local images.
export function guideFrom(file, source, slugs, { imageSize } = {}) {
  const slug = slugOf(file);
  if (!/^[a-z0-9][a-z0-9_-]*$/i.test(slug)) {
    throw new Error(`docs/${file}: the file name should be letters, digits, hyphens and underscores, so it makes a clean address.`);
  }
  const cleaned = withoutLicenceLine(source);
  let document;
  try {
    document = renderMarkdownDocument(cleaned, {
      rewriteLink: (href) => guideLink(href, slugs),
      rewriteImage: guideImage,
      imageSize,
    });
  } catch (error) {
    throw new Error(`docs/${file}: ${error.message}`);
  }
  const heading = document.headings.find((item) => item.sourceLevel === 1)?.text;
  if (!heading) throw new Error(`docs/${file}: needs a "# " heading on its first line.`);
  if (!document.firstParagraph) throw new Error(`docs/${file}: needs a paragraph under its heading.`);
  return {
    slug,
    file,
    heading,
    title: suffixedTitle(heading, "OrielOS guides"),
    description: truncate(document.firstParagraph),
    html: document.html,
    headings: document.headings,
  };
}

// Every guide from docs/, grouped and ordered for the index.
// files: [{ file, source }] for every docs/*.md but README.md.
export function guidesFrom(files, readme, options) {
  const docs = files.filter(({ file }) => file.endsWith(".md") && file !== "README.md");
  const slugs = new Set(docs.map(({ file }) => slugOf(file)));
  const blurbs = guideBlurbs(readme);
  const guides = docs.map(({ file, source }) => {
    const guide = guideFrom(file, source, slugs, options);
    const blurb = blurbs.get(guide.slug) ?? guide.description;
    return { ...guide, blurb: blurb.charAt(0).toUpperCase() + blurb.slice(1) };
  });
  const bySlug = new Map(guides.map((guide) => [guide.slug, guide]));
  const listed = new Set(GUIDE_GROUPS.flatMap((group) => group.slugs));
  const groups = GUIDE_GROUPS.map((group) => ({
    title: group.title,
    guides: group.slugs.filter((slug) => bySlug.has(slug)).map((slug) => bySlug.get(slug)),
  }));
  const more = guides
    .filter((guide) => !listed.has(guide.slug))
    .sort((a, b) => a.heading.localeCompare(b.heading, "en-GB"));
  groups.push({ title: "More", guides: more });
  return groups.filter((group) => group.guides.length > 0);
}

// Every ## and ### heading of every guide, A to Z, grouped by first letter.
export function topicIndex(groups) {
  const entries = [];
  for (const guide of groups.flatMap((group) => group.guides)) {
    for (const heading of guide.headings) {
      if (heading.sourceLevel !== 2 && heading.sourceLevel !== 3) continue;
      // "1. Download" is listed as "Download".
      const label = heading.text.replace(/^\d+[a-z]?[.)]\s+/i, "").trim();
      if (label === "") continue;
      entries.push({ label, href: `/guides/${guide.slug}/#${heading.id}`, guide: guide.heading });
    }
  }
  const collator = new Intl.Collator("en-GB", { sensitivity: "base", numeric: true });
  entries.sort((a, b) => collator.compare(a.label, b.label) || collator.compare(a.guide, b.guide));
  const letters = new Map();
  for (const entry of entries) {
    const first = entry.label.normalize("NFD")[0].toUpperCase();
    const letter = /[A-Z]/.test(first) ? first : /[0-9]/.test(first) ? "0–9" : "#";
    if (!letters.has(letter)) letters.set(letter, []);
    letters.get(letter).push(entry);
  }
  const order = (letter) => (letter === "#" ? 0 : letter === "0–9" ? 1 : 2);
  return [...letters.entries()]
    .sort(([a], [b]) => order(a) - order(b) || a.localeCompare(b))
    .map(([letter, items]) => ({ letter, id: `topics-${letter === "0–9" ? "0-9" : letter === "#" ? "other" : letter.toLowerCase()}`, entries: items }));
}

export function guidesIndexContent(groups) {
  const allSlugs = new Set(groups.flatMap((group) => group.guides.map((guide) => guide.slug)));
  const sections = groups.map((group) => {
    const id = `group-${slugify(group.title)}`;
    const items = group.guides
      .map(
        (guide) =>
          `<li><a class="guide-link" href="/guides/${guide.slug}/">${escapeHtml(guide.heading)}</a>` +
          `<p>${renderMarkdownInline(guide.blurb, { rewriteLink: (href) => guideLink(href, allSlugs) })}</p></li>`,
      )
      .join("\n      ");
    return (
      `<section class="guide-group" aria-labelledby="${id}">\n` +
      `    <h2 id="${id}">${escapeHtml(group.title)}</h2>\n` +
      `    <ul class="guide-list">\n      ${items}\n    </ul>\n  </section>`
    );
  });
  const topics = topicIndex(groups);
  const jump = topics.map((group) => `<li><a href="#${group.id}">${escapeHtml(group.letter)}</a></li>`).join("");
  const lists = topics
    .map(
      (group) =>
        `<section class="topic-group" aria-labelledby="${group.id}">\n` +
        `      <h3 id="${group.id}">${escapeHtml(group.letter)}</h3>\n      <ul>\n` +
        group.entries
          .map(
            (entry) =>
              `        <li><a href="${escapeHtml(entry.href)}">${escapeHtml(entry.label)}</a> <span class="topic-guide">${escapeHtml(entry.guide)}</span></li>`,
          )
          .join("\n") +
        `\n      </ul>\n    </section>`,
    )
    .join("\n    ");
  return `<h1 class="page-title">Guides</h1>
  <p class="lead">How to install OrielOS, find your way around it every day and set it up for games. The same guides are in the source code’s <code>docs</code> folder and the project’s wiki on GitHub.</p>
  ${sections.join("\n  ")}
  <section class="topics" id="topics" aria-labelledby="topics-title">
    <h2 id="topics-title">Find a topic</h2>
    <p>Every topic in the guides, A to Z. Use your browser’s find (Ctrl+F) to search this list.</p>
    <nav class="letters" aria-label="Topics by letter"><ul>${jump}</ul></nav>
    <div class="topic-groups">
    ${lists}
    </div>
  </section>
  <p class="help-line">Can’t find what you need? Ask in the <a href="${DISCUSSIONS_QA}">Q&amp;A category of GitHub Discussions</a>, or on <a href="${DISCORD}">Discord</a>.</p>`;
}

export function guideContent(guide, previous, next) {
  const pager = [
    previous
      ? `<a class="pager-prev" rel="prev" href="/guides/${previous.slug}/"><span>Previous</span> ${escapeHtml(previous.heading)}</a>`
      : "",
    next ? `<a class="pager-next" rel="next" href="/guides/${next.slug}/"><span>Next</span> ${escapeHtml(next.heading)}</a>` : "",
  ].join("");
  return `<nav class="breadcrumb" aria-label="Breadcrumb"><ol><li><a href="/guides/">Guides</a></li><li><span aria-current="page">${escapeHtml(guide.heading)}</span></li></ol></nav>
  <article class="prose">
${guide.html}
  </article>
  <div class="page-meta">
    <p>This guide is licensed under <a href="https://creativecommons.org/licenses/by-sa/4.0/">CC BY-SA 4.0</a>.</p>
    <p><a href="${BLOB}docs/${encodeURI(guide.file)}">Edit this guide on GitHub</a></p>
  </div>
  ${pager ? `<nav class="pager" aria-label="More guides">${pager}</nav>` : ""}`;
}

// ---------------------------------------------------------------------------
// News

// A news post from website/news/<slug>.md, checked.
export function postFrom(file, source) {
  const name = `website/news/${path.basename(file)}`;
  const slug = slugOf(file);
  if (!/^[a-z0-9][a-z0-9-]*$/.test(slug)) {
    throw new Error(`${name}: the file name should be lower-case letters, digits and hyphens, such as first-release.md.`);
  }
  const { data, body } = parseFrontMatter(source, name);
  const problems = [];
  const title = data.title ?? "";
  if (title === "") problems.push(`needs a "title".`);
  else if (title.length > MAX_TITLE) problems.push(`the title has ${title.length} characters; keep it to ${MAX_TITLE}.`);
  if (!isDate(data.date)) problems.push(`needs a "date" written YYYY-MM-DD.`);
  const summary = data.summary ?? "";
  if (summary === "") problems.push(`needs a "summary".`);
  else if (summary.length > MAX_SUMMARY) problems.push(`the summary has ${summary.length} characters; keep it to ${MAX_SUMMARY}.`);
  const image = checkImage(data, problems);
  if (body.trim() === "") problems.push("has no text below the front matter.");
  fail(name, problems);
  return { slug, file: name, title, date: data.date, summary, image, body };
}

// Every post, newest first. entries: [{ file, source }].
export function postsFrom(entries) {
  const posts = entries.filter(({ file }) => file.endsWith(".md")).map(({ file, source }) => postFrom(file, source));
  const seen = new Map();
  for (const post of posts) {
    if (seen.has(post.slug)) throw new Error(`${post.file}: another post, ${seen.get(post.slug)}, has the same address.`);
    seen.set(post.slug, post.file);
  }
  return posts.sort((a, b) => b.date.localeCompare(a.date) || a.slug.localeCompare(b.slug));
}

const absolute = (href) => (href.startsWith("/") && !href.startsWith("//") ? `${SITE}${href}` : href);

// A post's body as HTML; for the feed, links on this site are absolute.
export function postHtml(post, { forFeed = false, imageSize } = {}) {
  try {
    return renderMarkdownDocument(post.body, {
      rewriteLink: (href) => (forFeed ? absolute(href) : href),
      imageSize,
    }).html;
  } catch (error) {
    throw new Error(`${post.file}: ${error.message}`);
  }
}

export function postImage(post) {
  if (!post.image) return null;
  return { url: `${SITE}${post.image.path}`, alt: post.image.alt, width: post.image.width, height: post.image.height };
}

export function postContent(post, html) {
  const image = post.image;
  const size = image?.width && image?.height ? ` width="${image.width}" height="${image.height}"` : "";
  const figure = image
    ? `<figure class="post-image"><img src="${escapeHtml(image.path)}" alt="${escapeHtml(image.alt)}"${size} loading="eager" decoding="async"></figure>\n`
    : "";
  return `<nav class="breadcrumb" aria-label="Breadcrumb"><ol><li><a href="/news/">News</a></li><li><span aria-current="page">${escapeHtml(post.title)}</span></li></ol></nav>
  <article class="prose post">
    <h1 class="page-title">${escapeHtml(post.title)}</h1>
    <p class="post-date"><time datetime="${post.date}">${formatDate(post.date)}</time></p>
${figure}${html}
  </article>
  <p class="back-link"><a href="/news/">Back to news</a></p>`;
}

export function postHead(post) {
  const url = `${SITE}/news/${post.slug}/`;
  const data = {
    "@context": "https://schema.org",
    "@type": "BlogPosting",
    headline: post.title,
    description: post.summary,
    datePublished: post.date,
    url,
    mainEntityOfPage: url,
    image: postImage(post)?.url ?? DEFAULT_IMAGE.url,
    inLanguage: "en-GB",
    author: { "@type": "Organization", "@id": `${SITE}/#organization`, name: "OrielOS", url: `${SITE}/` },
    publisher: { "@type": "Organization", "@id": `${SITE}/#organization`, name: "OrielOS", url: `${SITE}/` },
  };
  return `<meta property="article:published_time" content="${post.date}T00:00:00Z">\n${jsonLd(data)}`;
}

export function newsIndexContent(posts) {
  const list =
    posts.length > 0
      ? `<ul class="news-list">\n      ${newsItems(posts, "h2")}\n    </ul>`
      : `<p class="empty-note">There’s no news yet. Follow the project on <a href="${REPO_URL}">GitHub</a> to hear when there is.</p>`;
  return `<h1 class="page-title">News</h1>
  <p class="lead">News from the OrielOS project, newest first. Subscribe to <a href="/news/feed.xml">the feed</a> to get new posts and releases in your feed reader.</p>
  ${list}`;
}

// ---------------------------------------------------------------------------
// Release notes

const isGitHubUrl = (value) => typeof value === "string" && value.startsWith("https://github.com/");

// A version tag such as v0.1.1 as [major, minor, patch], or null for any other tag.
export function versionParts(tag) {
  const match = /^v(\d+)\.(\d+)\.(\d+)$/.exec(tag);
  return match ? match.slice(1).map(Number) : null;
}

function compareVersions(a, b) {
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return 0;
}

// Releases from GitHub's list, newest first. Full releases are stable versions; pre-releases are
// testing builds, kept only when their tag is a version. A testing build is marked with the first
// stable version that includes it, if there is one yet. Drafts are left out.
export function releasesFrom(json, repo) {
  if (!Array.isArray(json)) return [];
  const releases = json
    .filter(
      (item) =>
        item !== null &&
        typeof item === "object" &&
        item.draft === false &&
        typeof item.tag_name === "string" &&
        item.tag_name !== "" &&
        (item.prerelease === false || (item.prerelease === true && versionParts(item.tag_name) !== null)) &&
        typeof item.published_at === "string" &&
        !Number.isNaN(Date.parse(item.published_at)),
    )
    .map((item) => ({
      name: typeof item.name === "string" && item.name.trim() !== "" ? item.name : item.tag_name,
      tag: item.tag_name,
      testing: item.prerelease === true,
      // The Withdraw workflow renames a withdrawn build's pre-release.
      withdrawn: item.prerelease === true && typeof item.name === "string" && item.name.endsWith("(testing, withdrawn)"),
      publishedAt: new Date(item.published_at).toISOString().replace(/\.000Z$/, "Z"),
      url: isGitHubUrl(item.html_url)
        ? item.html_url
        : `https://github.com/${repo}/releases/tag/${encodeURIComponent(item.tag_name)}`,
      body: typeof item.body === "string" ? item.body : "",
    }))
    .sort((a, b) => b.publishedAt.localeCompare(a.publishedAt));
  const stable = releases
    .filter((release) => !release.testing && versionParts(release.tag))
    .sort((a, b) => compareVersions(versionParts(a.tag), versionParts(b.tag)));
  for (const release of releases) {
    if (!release.testing) continue;
    const version = versionParts(release.tag);
    release.stableIn = stable.find((item) => compareVersions(versionParts(item.tag), version) >= 0)?.tag ?? null;
  }
  return releases;
}

// The newest testing build that no stable version includes yet and that wasn't withdrawn, or null.
export function latestTesting(releases) {
  const waiting = releases.filter((release) => release.testing && !release.stableIn && !release.withdrawn);
  waiting.sort((a, b) => compareVersions(versionParts(b.tag), versionParts(a.tag)));
  const newest = waiting[0];
  return newest ? { name: newest.name, version: newest.tag } : null;
}

export function releaseAnchor(release) {
  return `${SITE}/releases/#${encodeURIComponent(release.tag)}`;
}

// The release's notes as HTML, under the release's own h2.
export function releaseHtml(release) {
  return renderMarkdownDocument(release.body, {
    rewriteLink: (href) => repoLink(href),
    // Pictures in release notes live on GitHub, so they become links.
    rewriteImage: (src) => repoLink(src),
    topHeadingLevel: 3,
    idPrefix: `${slugify(release.tag) || "release"}-`,
    // Release notes come from GitHub as they are, so a picture without alt text doesn't stop the build.
    requireAlt: false,
  }).html;
}

export function releasesContent(releases) {
  if (releases.length === 0) {
    return `<h1 class="page-title">Release notes</h1>
  <p class="empty-note">No releases yet. When there are, their notes appear here and on <a href="${REPO_URL}/releases">GitHub’s releases page</a>.</p>`;
  }
  const articles = releases.map((release) => {
    const id = escapeHtml(release.tag);
    const date = release.publishedAt.slice(0, 10);
    const notes = releaseHtml(release);
    let channel = `<span class="release-channel">Stable</span>`;
    if (release.testing) {
      let stableIn = "<span>Not in a stable version yet</span>";
      if (release.withdrawn) stableIn = "<span>Withdrawn</span>";
      else if (release.stableIn) {
        stableIn = `<span>In stable <a href="#${escapeHtml(release.stableIn)}">${escapeHtml(release.stableIn)}</a></span>`;
      }
      channel = `<span class="release-channel release-channel-testing">Testing</span> ${stableIn}`;
    }
    return `<article class="release prose" id="${id}" aria-labelledby="${id}-title">
    <h2 id="${id}-title">${escapeHtml(release.name)}</h2>
    <p class="release-meta">${channel} <time datetime="${escapeHtml(release.publishedAt)}">${formatDate(date)}</time> <a href="${escapeHtml(release.url)}">This release on GitHub</a></p>
${notes || "<p>No notes for this release.</p>"}
  </article>`;
  });
  return `<h1 class="page-title">Release notes</h1>
  <p class="lead">What changed in each OrielOS version, newest first. <strong>Testing</strong> builds come first, one for each set of changes, on computers that chose the testing channel; each one says what’s new since the build before it. Once a build has been checked on real PCs it becomes the next <strong>stable</strong> version, which the download installs and every other computer gets. <a href="/download/">Download the latest</a>, or find every version on <a href="${REPO_URL}/releases">GitHub</a>.</p>
  ${articles.join("\n  ")}`;
}

// ---------------------------------------------------------------------------
// The feed

const iso = (date) => (date.length === 10 ? `${date}T00:00:00Z` : date);

export function postEntry(post, html) {
  const url = `${SITE}/news/${post.slug}/`;
  return { id: url, url, title: post.title, published: iso(post.date), summary: post.summary, html };
}

export function releaseEntry(release, html) {
  const url = releaseAnchor(release);
  return {
    id: url,
    url,
    title: `${release.name} released`,
    published: release.publishedAt,
    summary: `The release notes for OrielOS ${release.tag}.`,
    html,
  };
}

// An Atom 1.0 feed of the entries, newest first.
export function atomFeed(entries, { now = new Date() } = {}) {
  const sorted = [...entries].sort((a, b) => b.published.localeCompare(a.published) || a.id.localeCompare(b.id));
  const updated = sorted[0]?.published ?? now.toISOString().replace(/\.\d{3}Z$/, "Z");
  const x = escapeHtml;
  const items = sorted.map(
    (entry) => `  <entry>
    <id>${x(entry.id)}</id>
    <title>${x(entry.title)}</title>
    <link rel="alternate" type="text/html" href="${x(entry.url)}"/>
    <published>${x(entry.published)}</published>
    <updated>${x(entry.published)}</updated>
    <summary>${x(entry.summary)}</summary>
    <content type="html">${x(entry.html)}</content>
  </entry>`,
  );
  return [
    '<?xml version="1.0" encoding="utf-8"?>',
    '<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="en-GB">',
    `  <id>${SITE}/news/</id>`,
    "  <title>OrielOS news</title>",
    "  <subtitle>News and releases from the OrielOS project.</subtitle>",
    `  <link rel="self" type="application/atom+xml" href="${SITE}/news/feed.xml"/>`,
    `  <link rel="alternate" type="text/html" href="${SITE}/news/"/>`,
    `  <icon>${SITE}/favicon.svg</icon>`,
    `  <updated>${x(updated)}</updated>`,
    "  <author><name>OrielOS</name><uri>https://orielos.org/</uri></author>",
    ...items,
    "</feed>",
    "",
  ].join("\n");
}

// ---------------------------------------------------------------------------
// Pages from website/pages/

// A page from website/pages/<slug>.html or .md, checked.
export function contentPageFrom(file, source) {
  const name = `website/pages/${path.basename(file)}`;
  const slug = slugOf(file);
  const kind = file.endsWith(".md") ? "md" : "html";
  if (!/^[a-z0-9][a-z0-9-]*$/.test(slug)) {
    throw new Error(`${name}: the file name should be lower-case letters, digits and hyphens.`);
  }
  if (RESERVED.has(slug)) throw new Error(`${name}: /${slug}/ is made by the build, so a page can't use it.`);
  const { data, body } = parseFrontMatter(source, name);
  const problems = [];
  if (!data.title) problems.push(`needs a "title".`);
  if (!data.description) problems.push(`needs a "description".`);
  const image = checkImage(data, problems);
  fail(name, problems);
  return {
    slug,
    file: name,
    kind,
    title: data.title,
    heading: data.heading || data.title,
    description: data.description,
    image,
    body: kind === "html" ? stripLeadingComment(body) : body,
  };
}

export function contentPagesFrom(entries) {
  const pages = entries
    .filter(({ file }) => file.endsWith(".md") || file.endsWith(".html"))
    .map(({ file, source }) => contentPageFrom(file, source));
  const seen = new Map();
  for (const page of pages) {
    if (seen.has(page.slug)) throw new Error(`${page.file}: ${seen.get(page.slug)} has the same address, /${page.slug}/.`);
    seen.set(page.slug, page.file);
  }
  return pages.sort((a, b) => a.slug.localeCompare(b.slug));
}

// The HTML inside <main> for a content page. HTML pages go through renderPage
// first (build.mjs does that), Markdown pages through the renderer.
export function contentPageContent(page, html) {
  const classes = `content-page content-${page.slug}${page.kind === "md" ? " prose" : ""}`;
  return `<div class="${classes}">
  <h1 class="page-title">${escapeHtml(page.heading)}</h1>
${html}
  </div>`;
}

export function contentPageImage(page) {
  if (!page.image) return null;
  return { url: `${SITE}${page.image.path}`, alt: page.image.alt, width: page.image.width, height: page.image.height };
}

// artwork/CREDITS.md without its title and its note to contributors.
export function artworkCreditsHtml(source) {
  const lines = String(source).replace(/\r\n?/g, "\n").split("\n");
  const start = lines.findIndex((line) => /^# /.test(line));
  const rest = (start === -1 ? lines : lines.slice(start + 1))
    .join("\n")
    .replace(/[ \t]*Add a line here with every new file\./g, "");
  return renderMarkdownDocument(rest, {
    rewriteLink: (href) => repoLink(href, "artwork"),
    rewriteImage: (src) => repoLink(src, "artwork"),
    topHeadingLevel: 3,
    idPrefix: "artwork-",
  }).html;
}
