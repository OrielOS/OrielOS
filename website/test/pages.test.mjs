// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { checkPages, loadPartials, readHead, sumsFrom } from "../build.mjs";
import { htmlToText } from "../markdown.mjs";
import {
  DEFAULT_IMAGE,
  applyIncludes,
  artworkCreditsHtml,
  atomFeed,
  contentPageContent,
  contentPageFrom,
  contentPagesFrom,
  formatDate,
  guideContent,
  guideFrom,
  guideImage,
  guideLink,
  guidesFrom,
  guidesIndexContent,
  latestTesting,
  newsIndexContent,
  parseFrontMatter,
  postContent,
  postEntry,
  postFrom,
  postHead,
  postHtml,
  postsFrom,
  releaseEntry,
  releaseHtml,
  releasesContent,
  releasesFrom,
  renderLayout,
  renderPage,
  repoLink,
  topicIndex,
  truncate,
} from "../pages.mjs";

const read = (relative) => readFile(fileURLToPath(new URL(relative, import.meta.url)), "utf8");
const partials = await loadPartials();
const layout = await read("../templates/page.html");

// Visible text of each FAQ section. The structured data sits outside these
// sections, so the comparison is against the page copy.
function sectionTexts(html) {
  const texts = [];
  let from = 0;
  for (;;) {
    const start = html.indexOf("<section", from);
    if (start < 0) break;
    const end = html.indexOf("</section>", start);
    assert.ok(end > start);
    texts.push(htmlToText(html.slice(start, end)));
    from = end + "</section>".length;
  }
  return texts;
}

// A page through the shared layout, as the build makes it.
const layoutPage = (details) =>
  renderLayout(layout, partials, { title: "A page", description: "About the page.", url: "https://orielos.org/a/", content: "<p>Hi</p>", ...details });

// ---------------------------------------------------------------------------
// Layout

test("the header marks the current section and nothing else", () => {
  const html = applyIncludes("<!-- include:header -->", partials, { current: "guides" });
  assert.match(html, /<a href="\/guides\/" aria-current="page">Guides<\/a>/);
  assert.equal(html.match(/aria-current/g).length, 1);
  const home = applyIncludes("<!-- include:header -->", partials);
  assert.doesNotMatch(home, /aria-current|\{\{/);
});

test("the nav has the site's sections, with Download, Guides and GitHub on narrow screens", () => {
  const html = applyIncludes("<!-- include:header -->", partials);
  const items = [...html.matchAll(/<li( class="nav-extra")?><a href="([^"]+)"[^>]*>([^<]+)<\/a><\/li>/g)].map(
    ([, extra, href, label]) => ({ label, href, narrow: !extra }),
  );
  assert.deepEqual(items, [
    { label: "Download", href: "/download/", narrow: true },
    { label: "Guides", href: "/guides/", narrow: true },
    { label: "News", href: "/news/", narrow: false },
    { label: "Status", href: "/#status", narrow: false },
    { label: "Contribute", href: "/#contribute", narrow: false },
    { label: "GitHub", href: "https://github.com/ncjsvr/OrielOS", narrow: true },
  ]);
});

test("the footer links the site's pages and keeps the badges", () => {
  const html = applyIncludes("<!-- include:footer -->", partials);
  for (const href of ["/guides/", "/faq/", "/news/", "/releases/", "/press/", "/credits/", "https://github.com/ncjsvr/OrielOS/blob/main/SECURITY.md"]) {
    assert.ok(html.includes(`href="${href}"`), href);
  }
  assert.match(html, /bestpractices\.dev\/projects\/15906\/badge/);
  assert.doesNotMatch(html, /SPDX/);
});

test("unknown includes stop the build", () => {
  assert.throws(() => applyIncludes("<!-- include:sidebar -->", partials), /Unknown include/);
});

test("the layout makes a page that passes the search checks", () => {
  const html = layoutPage({ current: "news" });
  assert.doesNotThrow(() => checkPages([{ file: "a/index.html", url: "https://orielos.org/a/", html }]));
  const { meta, canonical } = readHead(html);
  assert.equal(canonical, "https://orielos.org/a/");
  assert.equal(meta["og:image"], DEFAULT_IMAGE.url);
  assert.equal(meta["og:image:width"], "1200");
  assert.equal(meta["og:image:height"], "630");
  assert.equal(meta["twitter:site"], "@BuiltByNath");
  assert.match(html, /<link rel="alternate" type="application\/atom\+xml" href="\/news\/feed\.xml" title="OrielOS news">/);
  assert.match(html, /<main id="main" class="page">/);
  assert.match(html, /<a href="\/news\/" aria-current="page">News<\/a>/);
  assert.match(html, /class="site-footer"/);
  assert.doesNotMatch(html, /\{\{|<!-- (?:head|content|include:)/);
});

test("the layout uses the home page's security policy", async () => {
  const home = await read("../public/index.html");
  const csp = (html) => /http-equiv="Content-Security-Policy" content="([^"]*)"/.exec(html)[1];
  assert.equal(csp(layoutPage()), csp(home));
  assert.equal(csp(await read("../public/404.html")), csp(home));
});

test("the layout escapes the page's details and never reads placeholders in the content", () => {
  const html = layoutPage({ title: 'Say "hi" & <bye>', content: "<p>{{title}} <!-- head --></p>" });
  assert.match(html, /<title>Say &quot;hi&quot; &amp; &lt;bye&gt;<\/title>/);
  assert.match(html, /<p>\{\{title\}\} <!-- head --><\/p>/);
});

test("a page's own image replaces the default in its link preview", () => {
  const html = layoutPage({ image: { url: "https://orielos.org/images/x.png", alt: "X", width: null, height: null } });
  const { meta } = readHead(html);
  assert.equal(meta["og:image"], "https://orielos.org/images/x.png");
  assert.equal(meta["og:image:alt"], "X");
  assert.equal(meta["og:image:width"], undefined);
});

test("the not-found page uses the shared header and footer and stays out of search", async () => {
  const html = renderPage(applyIncludes(await read("../public/404.html"), partials));
  assert.match(html, /class="site-header"/);
  assert.match(html, /class="site-footer"/);
  assert.match(html, /<meta name="robots" content="noindex">/);
  // It can be served at any address, so nothing on it is relative.
  for (const [, url] of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
    assert.match(url, /^(\/|#|https:\/\/|mailto:)/, url);
  }
});

test("the home page uses root-relative addresses", async () => {
  const html = renderPage(applyIncludes(await read("../public/index.html"), partials), {});
  for (const [, url] of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
    assert.match(url, /^(\/|#|https:\/\/|mailto:)/, url);
  }
});

// ---------------------------------------------------------------------------
// Guides

const slugs = new Set(["install", "updates", "status"]);

test("guide links go to guide pages, the index or GitHub", () => {
  assert.equal(guideLink("updates.md", slugs), "/guides/updates/");
  assert.equal(guideLink("install.md#make-room-next-to-windows", slugs), "/guides/install/#make-room-next-to-windows");
  assert.equal(guideLink("./status.md", slugs), "/guides/status/");
  assert.equal(guideLink("README.md", slugs), "/guides/");
  assert.equal(guideLink("README.md#x", slugs), "/guides/#x");
  assert.equal(guideLink("../CONTRIBUTING.md", slugs), "https://github.com/ncjsvr/OrielOS/blob/main/CONTRIBUTING.md");
  assert.equal(guideLink("LICENSE", slugs), "https://github.com/ncjsvr/OrielOS/blob/main/docs/LICENSE");
  assert.equal(guideLink("missing.md", slugs), "https://github.com/ncjsvr/OrielOS/blob/main/docs/missing.md");
  assert.equal(guideLink("../image/Containerfile", slugs), "https://github.com/ncjsvr/OrielOS/blob/main/image/Containerfile");
  assert.equal(guideLink("#the-update-settings", slugs), "#the-update-settings");
  assert.equal(guideLink("https://flathub.org", slugs), "https://flathub.org");
  assert.equal(guideLink("/download/", slugs), "/download/");
});

test("guide images are served from /guides/images/", () => {
  assert.equal(guideImage("images/install-welcome.png"), "/guides/images/install-welcome.png");
  assert.equal(guideImage("./images/a/b.webp"), "/guides/images/a/b.webp");
  assert.equal(guideImage("/images/screenshots/start.webp"), "/images/screenshots/start.webp");
});

const guideSource = [
  "# Updates and going back",
  "",
  "OrielOS updates in the background. A new version is prepared while you keep working, and nothing changes until you restart.",
  "If the new version gives you trouble, you go back to the one you had before, and OrielOS doesn't offer that version to you again.",
  "",
  "![The update page in Settings](images/update.png)",
  "",
  "## How updates arrive",
  "",
  "See [Install OrielOS](install.md#1-download), [the docs](README.md) and [the licence](LICENSE).",
  "",
  "### 1. The update settings",
  "",
  "Licence: CC BY-SA 4.0 (see `LICENSE` in this folder).",
].join("\n");

test("a guide's title, description, links and images come from its Markdown", () => {
  const guide = guideFrom("updates.md", guideSource, slugs, { imageSize: () => ({ width: 640, height: 400 }) });
  assert.equal(guide.slug, "updates");
  assert.equal(guide.heading, "Updates and going back");
  assert.equal(guide.title, "Updates and going back · OrielOS guides");
  assert.ok(guide.description.length <= 156);
  assert.ok(guide.description.endsWith("…"));
  assert.ok(guide.description.startsWith("OrielOS updates in the background. A new version is prepared"));
  assert.match(guide.html, /<a href="\/guides\/install\/#1-download">Install OrielOS<\/a>/);
  assert.match(guide.html, /<a href="\/guides\/">the docs<\/a>/);
  assert.match(guide.html, /<a href="https:\/\/github\.com\/ncjsvr\/OrielOS\/blob\/main\/docs\/LICENSE">the licence<\/a>/);
  assert.match(guide.html, /<figure class="doc-image"><img src="\/guides\/images\/update\.png" alt="The update page in Settings" width="640" height="400"/);
  assert.doesNotMatch(guide.html, /Licence: CC BY-SA/);
});

test("a long guide heading drops the suffix from the title", () => {
  const heading = "A".repeat(60);
  const guide = guideFrom("long.md", `# ${heading}\n\nText.`, slugs);
  assert.equal(guide.title, heading);
});

test("a guide without a heading, or an image without alt text, stops the build with the file's name", () => {
  assert.throws(() => guideFrom("x.md", "Just text.", slugs), /docs\/x\.md: needs a "# " heading/);
  assert.throws(() => guideFrom("y.md", "# Y\n\nText.\n\n![](images/a.png)", slugs), /docs\/y\.md: an image has no alt text/);
});

test("truncate cuts at a word boundary", () => {
  assert.equal(truncate("Short."), "Short.");
  const long = "word ".repeat(60);
  const cut = truncate(long, 155);
  assert.ok(cut.length <= 156);
  assert.match(cut, /word…$/);
});

const docs = [
  { file: "README.md", source: "# docs\n\n- [Install OrielOS](install.md): download the installer and **install** it.\n- [Updates](updates.md): how updates work.\n" },
  { file: "install.md", source: "# Install OrielOS\n\nHow to install.\n\n## 1. Download\n\n## What you need\n" },
  { file: "updates.md", source: "# Updates and going back\n\nHow updates work.\n\n## What you need\n\n### Boot menu\n\n#### Too deep\n" },
  { file: "zebra.md", source: "# Zebra crossings\n\nAn unlisted guide.\n\n## Ácute start\n" },
  { file: "notes.txt", source: "ignored" },
];

test("guides are grouped and ordered, and unlisted ones go into More", () => {
  const groups = guidesFrom(docs, docs[0].source);
  assert.deepEqual(
    groups.map((group) => [group.title, group.guides.map((guide) => guide.slug)]),
    [["Get started", ["install"]], ["Everyday use", ["updates"]], ["More", ["zebra"]]],
  );
  assert.equal(groups[0].guides[0].blurb, "Download the installer and **install** it.");
  assert.equal(groups[2].guides[0].blurb, "An unlisted guide.");
});

test("the topic index lists every ## and ### heading, A to Z", () => {
  const topics = topicIndex(guidesFrom(docs, docs[0].source));
  assert.deepEqual(topics.map((group) => group.letter), ["A", "B", "D", "W"]);
  assert.deepEqual(topics.find((group) => group.letter === "A").entries, [
    { label: "Ácute start", href: "/guides/zebra/#ácute-start", guide: "Zebra crossings" },
  ]);
  assert.deepEqual(topics.find((group) => group.letter === "D").entries[0], {
    label: "Download",
    href: "/guides/install/#1-download",
    guide: "Install OrielOS",
  });
  assert.deepEqual(
    topics.find((group) => group.letter === "W").entries.map((entry) => entry.guide),
    ["Install OrielOS", "Updates and going back"],
  );
  assert.ok(!topics.flatMap((group) => group.entries).some((entry) => entry.label === "Too deep"));
});

test("the guides index has the groups, the topic index and the help line", () => {
  const html = guidesIndexContent(guidesFrom(docs, docs[0].source));
  assert.match(html, /<h1 class="page-title">Guides<\/h1>/);
  assert.match(html, /<h2 id="group-get-started">Get started<\/h2>/);
  assert.match(html, /<strong>install<\/strong>/);
  assert.match(html, /Every topic in the guides, A to Z\. Use your browser’s find \(Ctrl\+F\) to search this list\./);
  assert.match(html, /<a href="#topics-a">A<\/a>/);
  assert.match(html, /<h3 id="topics-a">A<\/h3>/);
  assert.match(html, /discussions\/categories\/q-a/);
  assert.match(html, /discord\.gg\/RnpZYaKbHA/);
});

test("a guide page has a breadcrumb, an edit link and previous and next links", () => {
  const [install, updates, zebra] = guidesFrom(docs, docs[0].source).flatMap((group) => group.guides);
  const html = guideContent(updates, install, zebra);
  assert.match(html, /<nav class="breadcrumb" aria-label="Breadcrumb"><ol><li><a href="\/guides\/">Guides<\/a><\/li><li><span aria-current="page">Updates and going back<\/span>/);
  assert.match(html, /This guide is licensed under <a [^>]*>CC BY-SA 4\.0<\/a>\./);
  assert.match(html, /<a href="https:\/\/github\.com\/ncjsvr\/OrielOS\/blob\/main\/docs\/updates\.md">Edit this guide on GitHub<\/a>/);
  assert.match(html, /rel="prev" href="\/guides\/install\/"/);
  assert.match(html, /rel="next" href="\/guides\/zebra\/"/);
  assert.doesNotMatch(guideContent(install, undefined, updates), /rel="prev"/);
});

test("the real docs make valid guides", async () => {
  const { readdir } = await import("node:fs/promises");
  const dir = fileURLToPath(new URL("../../docs/", import.meta.url));
  const files = await Promise.all(
    (await readdir(dir)).filter((file) => file.endsWith(".md")).map(async (file) => ({ file, source: await readFile(dir + file, "utf8") })),
  );
  const groups = guidesFrom(files, files.find(({ file }) => file === "README.md").source);
  const guides = groups.flatMap((group) => group.guides);
  assert.ok(guides.some((guide) => guide.slug === "install"));
  assert.equal(groups[0].guides[0].slug, "install");
  for (const guide of guides) {
    assert.ok(guide.title.length <= 70, guide.title);
    assert.ok(guide.description.length <= 160, guide.description);
    assert.doesNotMatch(guide.html, /Licence: CC BY-SA|href="(?!https:)[^"#]*\.md/, guide.slug);
  }
});

// ---------------------------------------------------------------------------
// News

const post = (front, body = "Body text.") => `---\n${front}\n---\n\n${body}\n`;
const valid = "title: First post\ndate: 2026-10-27\nsummary: What happened.";

test("front matter is read as key: value lines", () => {
  assert.deepEqual(parseFrontMatter("---\ntitle: Press kit: facts\n# a comment\nquoted: \"x\"\n---\nBody"), {
    data: { title: "Press kit: facts", quoted: "x" },
    body: "Body",
  });
  assert.deepEqual(parseFrontMatter("---\r\ntitle: A\r\n---\r\n\r\nBody\r\n").data, { title: "A" });
  assert.throws(() => parseFrontMatter("No front matter", "x.md"), /x\.md: needs front matter/);
  assert.throws(() => parseFrontMatter("---\ntitle: A\n", "x.md"), /no closing/);
  assert.throws(() => parseFrontMatter("---\njust words\n---\n", "x.md"), /line 2 isn't "key: value"/);
  assert.throws(() => parseFrontMatter("---\na: 1\na: 2\n---\n", "x.md"), /sets "a" twice/);
});

test("a post needs a title, a date and a summary, and alt text for its image", () => {
  const ok = postFrom("first-post.md", post(valid));
  assert.equal(ok.slug, "first-post");
  assert.equal(ok.date, "2026-10-27");
  assert.equal(ok.image, null);
  const fails = (front, pattern, file = "x.md") => assert.throws(() => postFrom(file, post(front)), pattern);
  fails("date: 2026-10-27\nsummary: S", /website\/news\/x\.md: needs a "title"/);
  fails("title: T\nsummary: S", /needs a "date" written YYYY-MM-DD/);
  fails("title: T\ndate: 2026-02-30\nsummary: S", /needs a "date"/);
  fails("title: T\ndate: 27/10/2026\nsummary: S", /needs a "date"/);
  fails("title: T\ndate: 2026-10-27", /needs a "summary"/);
  fails(`title: T\ndate: 2026-10-27\nsummary: ${"x".repeat(161)}`, /summary has 161 characters/);
  fails(`title: ${"x".repeat(71)}\ndate: 2026-10-27\nsummary: S`, /title has 71 characters/);
  fails(`${valid}\nimage: /images/a.png`, /needs "image_alt"/);
  fails(`${valid}\nimage: https://example.com/a.png\nimage_alt: A`, /should be a path on the site/);
  fails(`${valid}\nimage: /images/../secret.png\nimage_alt: A`, /should be a path on the site/);
  fails(`${valid}\nimage: /images/a.png\nimage_alt: A\nimage_width: wide`, /"image_width" should be a whole number/);
  fails(`${valid}\nimage_alt: A`, /"image_alt" needs an "image"/);
  fails(valid, /file name should be lower-case/, "First Post.md");
  assert.throws(() => postFrom("x.md", "---\n" + valid + "\n---\n"), /no text below the front matter/);
});

test("a post's image, with its size when given", () => {
  const withImage = postFrom("p.md", post(`${valid}\nimage: /images/screenshots/start.webp\nimage_alt: Start open\nimage_width: 1280\nimage_height: 800`));
  assert.deepEqual(withImage.image, { path: "/images/screenshots/start.webp", alt: "Start open", width: 1280, height: 800 });
  const html = postContent(withImage, postHtml(withImage));
  assert.match(
    html,
    /<figure class="post-image"><img src="\/images\/screenshots\/start\.webp" alt="Start open" width="1280" height="800" loading="eager" decoding="async"><\/figure>/,
  );
  const page = layoutPage({ image: { url: "https://orielos.org/images/screenshots/start.webp", alt: "Start open", width: 1280, height: 800 } });
  assert.equal(readHead(page).meta["og:image:width"], "1280");
});

test("posts are sorted newest first and need different addresses", () => {
  const posts = postsFrom([
    { file: "older.md", source: post("title: Older\ndate: 2026-01-02\nsummary: Old.") },
    { file: "newer.md", source: post("title: Newer\ndate: 2026-10-27\nsummary: New.") },
    { file: "same-day.md", source: post("title: Same day\ndate: 2026-10-27\nsummary: Also new.") },
    { file: ".gitkeep", source: "" },
  ]);
  assert.deepEqual(posts.map((item) => item.slug), ["newer", "same-day", "older"]);
  assert.throws(
    () => postsFrom([{ file: "a.md", source: post(valid) }, { file: "sub/a.md", source: post(valid) }]),
    /same address/,
  );
});

test("a post page has its date, body, way back and structured data", () => {
  const item = postFrom("first-post.md", post(valid, "## Who it's for\n\nSee [the guides](/guides/)."));
  const html = postContent(item, postHtml(item));
  assert.match(html, /<h1 class="page-title">First post<\/h1>/);
  assert.match(html, /<time datetime="2026-10-27">27 October 2026<\/time>/);
  assert.match(html, /<h2 id="who-its-for">/);
  assert.match(html, /<a href="\/news\/">Back to news<\/a>/);
  const head = postHead(item);
  assert.match(head, /<meta property="article:published_time" content="2026-10-27T00:00:00Z">/);
  const data = JSON.parse(/<script type="application\/ld\+json">([\s\S]*)<\/script>/.exec(head)[1]);
  assert.equal(data["@type"], "BlogPosting");
  assert.equal(data.headline, "First post");
  assert.equal(data.datePublished, "2026-10-27");
  assert.equal(data.url, "https://orielos.org/news/first-post/");
  assert.equal(data.author["@id"], "https://orielos.org/#organization");
  assert.equal(data.publisher["@id"], "https://orielos.org/#organization");
  assert.equal(data.image, DEFAULT_IMAGE.url);
  const page = layoutPage({ url: "https://orielos.org/news/first-post/", ogType: "article", head, content: html });
  assert.doesNotThrow(() => checkPages([{ file: "news/first-post/index.html", url: "https://orielos.org/news/first-post/", html: page }]));
  assert.equal(readHead(page).meta["og:type"], "article");
});

test("structured data can't close its script element", () => {
  const item = postFrom("x.md", post("title: </script><script>alert(1)\ndate: 2026-10-27\nsummary: S"));
  assert.doesNotMatch(postHead(item), /<\/script><script>/);
});

test("the news page lists posts newest first, or says there are none", () => {
  const posts = postsFrom([
    { file: "a.md", source: post("title: A <b>\ndate: 2026-01-01\nsummary: About A & more.") },
    { file: "b.md", source: post("title: B\ndate: 2026-02-01\nsummary: About B.") },
  ]);
  const html = newsIndexContent(posts);
  assert.ok(html.indexOf("/news/b/") < html.indexOf("/news/a/"));
  assert.match(html, /A &lt;b&gt;/);
  assert.match(html, /About A &amp; more\./);
  assert.match(html, /1 January 2026/);
  assert.match(newsIndexContent([]), /There’s no news yet/);
});

test("the home page shows the three newest posts, or no news section", async () => {
  const home = applyIncludes(await read("../public/index.html"), partials);
  const posts = postsFrom(
    ["2026-01-01", "2026-02-01", "2026-03-01", "2026-04-01"].map((date, index) => ({
      file: `p${index}.md`,
      source: post(`title: Post ${index}\ndate: ${date}\nsummary: Summary ${index}.`),
    })),
  );
  const html = renderPage(home, { news: posts });
  assert.match(html, /<section class="section" id="news"/);
  assert.deepEqual([...html.matchAll(/href="\/news\/(p\d)\/"/g)].map((match) => match[1]), ["p3", "p2", "p1"]);
  assert.match(html, /<a href="\/news\/">All news<\/a>/);
  assert.match(html, /<a href="\/news\/feed\.xml">Subscribe to the feed<\/a>/);
  assert.ok(html.indexOf('id="news"') < html.indexOf('id="contribute"'));
  const empty = renderPage(home, { news: [] });
  assert.doesNotMatch(empty, /id="news"/);
});

test("formatDate writes dates in British style", () => {
  assert.equal(formatDate("2026-10-27"), "27 October 2026");
  assert.equal(formatDate("2026-01-05T12:00:00Z"), "5 January 2026");
});

// ---------------------------------------------------------------------------
// Releases and the feed

const releaseJson = [
  { tag_name: "v0.0.6", name: "", draft: false, prerelease: false, published_at: "2026-10-20T10:00:00Z", html_url: "https://github.com/ncjsvr/OrielOS/releases/tag/v0.0.6", body: "## Added\n\n- Older." },
  { tag_name: "v0.0.8-rc", name: "Candidate", draft: false, prerelease: true, published_at: "2026-10-28T10:00:00Z", html_url: "https://github.com/x", body: "" },
  { tag_name: "v0.0.9", name: "Draft", draft: true, prerelease: false, published_at: null, html_url: "https://github.com/x", body: "" },
  {
    tag_name: "v0.0.7",
    name: "OrielOS v0.0.7",
    draft: false,
    prerelease: false,
    published_at: "2026-10-27T15:04:05Z",
    html_url: "https://evil.example/x",
    body: "## Get it\n\nSee [install](docs/install.md) and <script>alert(1)</script>.\n\n### Added\n\n- **New** thing ![](https://example.com/x.png)",
  },
  null,
  { tag_name: "", draft: false, prerelease: false, published_at: "2026-10-27T15:04:05Z" },
];

test("release notes keep only full releases, newest first", () => {
  const releases = releasesFrom(releaseJson, "ncjsvr/OrielOS");
  assert.deepEqual(releases.map((release) => release.tag), ["v0.0.7", "v0.0.6"]);
  assert.equal(releases[0].name, "OrielOS v0.0.7");
  assert.equal(releases[1].name, "v0.0.6");
  assert.equal(releases[0].url, "https://github.com/ncjsvr/OrielOS/releases/tag/v0.0.7");
  assert.equal(releases[0].publishedAt, "2026-10-27T15:04:05Z");
  assert.deepEqual(releasesFrom({ message: "Not Found" }, "a/b"), []);
});

test("release notes are rendered safely, with links to GitHub and headings under the release's own", () => {
  const [latest] = releasesFrom(releaseJson, "ncjsvr/OrielOS");
  const html = releaseHtml(latest);
  assert.match(html, /<h3 id="v007-get-it">Get it<\/h3>/);
  assert.match(html, /<h4 id="v007-added">Added<\/h4>/);
  assert.match(html, /href="https:\/\/github\.com\/ncjsvr\/OrielOS\/blob\/main\/docs\/install\.md"/);
  assert.match(html, /&lt;script&gt;/);
  assert.doesNotMatch(html, /<script|<img/);
  const page = releasesContent(releasesFrom(releaseJson, "ncjsvr/OrielOS"));
  assert.match(page, /<article class="release prose" id="v0\.0\.7"/);
  assert.match(page, /<time datetime="2026-10-27T15:04:05Z">27 October 2026<\/time>/);
  assert.ok(page.indexOf('id="v0.0.7"') < page.indexOf('id="v0.0.6"'));
  assert.match(releasesContent([]), /No releases yet\..*github\.com\/ncjsvr\/OrielOS\/releases/s);
});

const channelJson = [
  { tag_name: "v0.0.7", name: "OrielOS v0.0.7", draft: false, prerelease: false, published_at: "2026-10-27T10:00:00Z", body: "Stable." },
  { tag_name: "v0.0.8", name: "OrielOS v0.0.8 (testing)", draft: false, prerelease: true, published_at: "2026-10-27T11:00:00Z", body: "Eight." },
  { tag_name: "v0.0.9", name: "OrielOS v0.0.9", draft: false, prerelease: false, published_at: "2026-10-27T12:00:00Z", body: "Nine." },
  { tag_name: "v0.0.10", name: "OrielOS v0.0.10 (testing)", draft: false, prerelease: true, published_at: "2026-10-27T13:00:00Z", body: "Ten." },
  { tag_name: "v0.1.0", name: "OrielOS v0.1.0 (testing)", draft: false, prerelease: true, published_at: "2026-10-27T14:00:00Z", body: "Eleven." },
];

test("testing builds are kept and marked with the stable version that includes them", () => {
  const releases = releasesFrom(channelJson, "ncjsvr/OrielOS");
  assert.deepEqual(
    releases.map((release) => [release.tag, release.testing, release.stableIn]),
    [
      ["v0.1.0", true, null],
      ["v0.0.10", true, null],
      ["v0.0.9", false, undefined],
      ["v0.0.8", true, "v0.0.9"],
      ["v0.0.7", false, undefined],
    ],
  );
  assert.deepEqual(latestTesting(releases), { name: "OrielOS v0.1.0 (testing)", version: "v0.1.0" });
  assert.equal(latestTesting(releasesFrom(channelJson.slice(0, 3), "ncjsvr/OrielOS")), null);
  assert.equal(latestTesting([]), null);
});

test("a withdrawn testing build is labelled and never offered as the newest", () => {
  const withdrawn = { ...channelJson[4], name: "OrielOS v0.1.0 (testing, withdrawn)" };
  const releases = releasesFrom([...channelJson.slice(0, 4), withdrawn], "ncjsvr/OrielOS");
  assert.equal(releases[0].withdrawn, true);
  assert.deepEqual(latestTesting(releases), { name: "OrielOS v0.0.10 (testing)", version: "v0.0.10" });
  const page = releasesContent(releases);
  assert.match(page, /Testing<\/span> <span>Withdrawn<\/span>/);
});

test("the release notes label testing builds and say which stable version has them", () => {
  const page = releasesContent(releasesFrom(channelJson, "ncjsvr/OrielOS"));
  const article = (tag) => page.slice(page.indexOf(`id="${tag}"`), page.indexOf("</article>", page.indexOf(`id="${tag}"`)));
  assert.match(article("v0.0.8"), /<span class="release-channel release-channel-testing">Testing<\/span> <span>In stable <a href="#v0\.0\.9">v0\.0\.9<\/a><\/span>/);
  assert.match(article("v0.1.0"), /Testing<\/span> <span>Not in a stable version yet<\/span>/);
  assert.match(article("v0.0.9"), /<span class="release-channel">Stable<\/span> <time/);
  assert.match(page, /<strong>Testing<\/strong> builds come first/);
});

test("renderPage names the newest testing build only when there is one", () => {
  const template = "<p>Stable.<!-- if:testing --> Testing: <a href=\"{{testing.url}}\">{{testing.version}}</a>.<!-- end:testing --><!-- if:no-testing --> None.<!-- end:no-testing --></p>";
  assert.equal(
    renderPage(template, { testing: { name: "OrielOS v0.1.0 (testing)", version: "v0.1.0" } }),
    '<p>Stable. Testing: <a href="/releases/#v0.1.0">v0.1.0</a>.</p>',
  );
  assert.equal(renderPage(template, {}), "<p>Stable. None.</p>");
  assert.equal(renderPage(template, { testing: { version: "<b>" } }), "<p>Stable. None.</p>");
  assert.throws(() => renderPage("<p>{{testing.version}}</p>", {}), /unresolved marker: \{\{testing\./);
});

test("repoLink sends relative paths to GitHub", () => {
  assert.equal(repoLink("CHANGELOG.md"), "https://github.com/ncjsvr/OrielOS/blob/main/CHANGELOG.md");
  assert.equal(repoLink("./docs/install.md#x"), "https://github.com/ncjsvr/OrielOS/blob/main/docs/install.md#x");
  assert.equal(repoLink("logo/a.svg", "artwork"), "https://github.com/ncjsvr/OrielOS/blob/main/artwork/logo/a.svg");
  assert.equal(repoLink("../.github/x.png", "artwork"), "https://github.com/ncjsvr/OrielOS/blob/main/.github/x.png");
  assert.equal(repoLink("https://example.com"), "https://example.com");
});

test("the feed lists posts and releases newest first, with escaped content", () => {
  const posts = postsFrom([{ file: "hello.md", source: post("title: Hello & <welcome>\ndate: 2026-10-28\nsummary: A \"post\".", "See [the guides](/guides/) & **more**.") }]);
  const releases = releasesFrom(releaseJson, "ncjsvr/OrielOS");
  const xml = atomFeed([
    ...posts.map((item) => postEntry(item, postHtml(item, { forFeed: true }))),
    ...releases.map((item) => releaseEntry(item, releaseHtml(item))),
  ]);
  assert.match(xml, /^<\?xml version="1\.0" encoding="utf-8"\?>\n<feed xmlns="http:\/\/www\.w3\.org\/2005\/Atom" xml:lang="en-GB">/);
  assert.match(xml, /<id>https:\/\/orielos\.org\/news\/<\/id>/);
  assert.match(xml, /<title>OrielOS news<\/title>/);
  assert.match(xml, /<link rel="self" type="application\/atom\+xml" href="https:\/\/orielos\.org\/news\/feed\.xml"\/>/);
  assert.match(xml, /<link rel="alternate" type="text\/html" href="https:\/\/orielos\.org\/news\/"\/>/);
  assert.match(xml, /<updated>2026-10-28T00:00:00Z<\/updated>/);
  const ids = [...xml.matchAll(/<entry>\s*<id>([^<]+)<\/id>/g)].map((match) => match[1]);
  assert.deepEqual(ids, [
    "https://orielos.org/news/hello/",
    "https://orielos.org/releases/#v0.0.7",
    "https://orielos.org/releases/#v0.0.6",
  ]);
  assert.match(xml, /<title>Hello &amp; &lt;welcome&gt;<\/title>/);
  assert.match(xml, /<summary>A &quot;post&quot;\.<\/summary>/);
  assert.match(xml, /<published>2026-10-27T15:04:05Z<\/published>/);
  // The content is HTML, escaped once more for XML, with absolute links.
  assert.match(xml, /<content type="html">&lt;p&gt;See &lt;a href=&quot;https:\/\/orielos\.org\/guides\/&quot;&gt;the guides&lt;\/a&gt; &amp;amp; &lt;strong&gt;more&lt;\/strong&gt;\.&lt;\/p&gt;<\/content>/);
  // Well formed: every element closed, and no raw markup or bare ampersands inside text.
  const entries = xml.match(/<entry>[\s\S]*?<\/entry>/g);
  assert.equal(entries.length, 3);
  for (const entry of entries) {
    for (const element of ["id", "title", "published", "updated", "summary", "content"]) {
      assert.match(entry, new RegExp(`<${element}\\b[^>]*>[^<]*</${element}>`), element);
    }
  }
  assert.doesNotMatch(xml.replace(/&(?:amp|lt|gt|quot|#39);/g, ""), /&/);
});

test("an empty feed still builds", () => {
  const xml = atomFeed([], { now: new Date("2026-10-27T12:00:00.000Z") });
  assert.match(xml, /<updated>2026-10-27T12:00:00Z<\/updated>/);
  assert.doesNotMatch(xml, /<entry>/);
  assert.match(xml, /<\/feed>\n$/);
});

// ---------------------------------------------------------------------------
// Download and content pages

const downloadSource = await read("../pages/download.html");

test("the download page shows the installer, its checksums and how to check them", () => {
  const page = contentPageFrom("download.html", downloadSource);
  assert.equal(page.slug, "download");
  assert.doesNotMatch(page.body, /SPDX/);
  const iso = { url: "https://github.com/ncjsvr/OrielOS/releases/download/v0.0.7/OrielOS.iso", size: "1.2 GB", sha256: "a".repeat(64) };
  const release = { name: "v0.0.7", url: "https://github.com/ncjsvr/OrielOS/releases/tag/v0.0.7", iso };
  const sums = { url: "https://github.com/ncjsvr/OrielOS/releases/download/v0.0.7/SHA256SUMS" };
  const html = renderPage(page.body, { release, sums });
  assert.ok(html.includes(`href="${iso.url}"`));
  assert.ok(html.includes(`<code translate="no">${iso.sha256}</code>`));
  assert.ok(html.includes(`href="${sums.url}"`));
  assert.match(html, /Get-FileHash \.\\OrielOS\.iso/);
  assert.match(html, /shasum -a 256 OrielOS\.iso/);
  assert.match(html, /sha256sum OrielOS\.iso/);
  assert.match(html, /sha256sum -c SHA256SUMS --ignore-missing/);
  assert.match(html, /What you’ll need/);
  assert.match(html, /href="\/guides\/install\/"/);
  assert.match(html, /href="\/releases\/"/);
  assert.match(html, /href="https:\/\/github\.com\/ncjsvr\/OrielOS\/releases"/);

  const noSums = renderPage(page.body, { release });
  assert.doesNotMatch(noSums, /SHA256SUMS --ignore-missing|\{\{sums/);
  assert.match(noSums, /sha256sum OrielOS\.iso/);

  const nothing = renderPage(page.body, {});
  assert.match(nothing, /Nothing to download yet/);
  assert.doesNotMatch(nothing, /Check your download|Download the installer/);
  assert.match(nothing, /What you’ll need/);
});

test("sumsFrom finds the SHA256SUMS asset", () => {
  const asset = { name: "SHA256SUMS", state: "uploaded", browser_download_url: "https://github.com/a/b/releases/download/v1/SHA256SUMS" };
  assert.deepEqual(sumsFrom([{ name: "x.iso" }, asset]), { url: asset.browser_download_url });
  assert.equal(sumsFrom([{ ...asset, name: "SHA256SUMS.asc" }]), null);
  assert.equal(sumsFrom([{ ...asset, state: "starter" }]), null);
  assert.equal(sumsFrom([{ ...asset, browser_download_url: "https://evil.example/SHA256SUMS" }]), null);
  assert.equal(sumsFrom(undefined), null);
});

test("content pages take their titles, heading and image from front matter", () => {
  const html = contentPageFrom(
    "about.html",
    "---\ntitle: About OrielOS: the project\nheading: About\ndescription: What the project is.\nimage: /images/screenshots/desktop.png\nimage_alt: The desktop\n---\n<!--\nSPDX-License-Identifier: GPL-3.0-or-later\n-->\n<p><!-- if:release -->{{release.name}}<!-- end:release --></p>",
  );
  assert.equal(html.title, "About OrielOS: the project");
  assert.equal(html.heading, "About");
  assert.deepEqual(html.image, { path: "/images/screenshots/desktop.png", alt: "The desktop", width: null, height: null });
  assert.equal(renderPage(html.body, { release: { name: "v1", url: "https://github.com/x", iso: null } }), "<p>v1</p>");
  assert.match(contentPageContent(html, "<p>x</p>"), /<h1 class="page-title">About<\/h1>/);

  const markdown = contentPageFrom("faq.md", "---\ntitle: FAQ\ndescription: Questions.\n---\n# Ignored? No\n\nText.");
  assert.equal(markdown.kind, "md");
  assert.equal(markdown.heading, "FAQ");
  assert.match(contentPageContent(markdown, "<p>x</p>"), /class="content-page content-faq prose"/);

  assert.throws(() => contentPageFrom("x.html", "---\ntitle: X\n---\n"), /website\/pages\/x\.html: needs a "description"/);
  assert.throws(() => contentPageFrom("guides.html", "---\ntitle: X\ndescription: Y\n---\n"), /made by the build/);
  assert.throws(
    () => contentPagesFrom([{ file: "a.html", source: "---\ntitle: A\ndescription: A\n---\n" }, { file: "a.md", source: "---\ntitle: B\ndescription: B\n---\n" }]),
    /same address/,
  );
});

test("the FAQ page's structured data repeats the answers on the page", async () => {
  const item = contentPageFrom("faq.html", await read("../pages/faq.html"));
  assert.equal(item.title, "OrielOS FAQ: download, hardware and games");
  assert.equal(item.heading, "FAQ");
  const release = { name: "OrielOS v0.0.7", version: "v0.0.7", url: "https://github.com/ncjsvr/OrielOS/releases/tag/v0.0.7", iso: null };
  const rendered = (data) => {
    const body = renderPage(item.body, data);
    return {
      body,
      html: layoutPage({
        title: item.title,
        description: item.description,
        url: "https://orielos.org/faq/",
        content: contentPageContent(item, body),
      }),
    };
  };
  const { body, html } = rendered({ release });
  assert.doesNotThrow(() => checkPages([{ file: "faq/index.html", url: "https://orielos.org/faq/", html }]));
  const data = JSON.parse(readHead(html).scripts.find((script) => script.type === "application/ld+json").body);
  assert.equal(data["@type"], "FAQPage");
  assert.equal(data.url, "https://orielos.org/faq/");
  const texts = sectionTexts(body);
  assert.equal(data.mainEntity.length, 8);
  assert.equal(texts.length, data.mainEntity.length);
  for (const [question, text] of data.mainEntity.map((question, index) => [question, texts[index]])) {
    assert.equal(question["@type"], "Question");
    assert.equal(question.acceptedAnswer["@type"], "Answer");
    assert.ok(text.includes(question.name), question.name);
    assert.ok(text.includes(question.acceptedAnswer.text), question.name);
  }
  assert.match(texts[1], /The current stable release is v0\.0\.7/);
  const offline = rendered({});
  const offlineData = JSON.parse(readHead(offline.html).scripts.find((script) => script.type === "application/ld+json").body);
  assert.match(offlineData.mainEntity[1].acceptedAnswer.text, /An installer will be published with the first stable release/);
  assert.match(sectionTexts(offline.body)[1], /An installer will be published with the first stable release/);
  assert.doesNotMatch(offline.html, /\{\{release\.version\}\}/);
});

test("the credits page includes the artwork credits from artwork/CREDITS.md", async () => {
  const source = await read("../../artwork/CREDITS.md");
  const credits = artworkCreditsHtml(source);
  assert.doesNotMatch(credits, /<h[12]\b|Artwork credits<|Add a line here/);
  assert.match(credits, /<h3 id="artwork-fonts">Fonts<\/h3>/);
  assert.match(credits, /<div class="table-wrap">/);
  const page = contentPageFrom("credits.html", await read("../pages/credits.html"));
  const html = renderPage(page.body, { artworkCredits: credits });
  assert.match(html, /The projects OrielOS is built on/);
  assert.match(html, /Simple Icons/);
  assert.match(html, /OrielOS is not affiliated with Microsoft\. Windows is a trademark of Microsoft Corporation\./);
  assert.ok(html.includes(credits));
  assert.throws(() => renderPage(page.body, {}), /unresolved marker: <!-- artwork-credits -->/);
});

test("artwork credits drop only the title and the note to contributors", () => {
  const html = artworkCreditsHtml("# Artwork credits\n\nEvery file. Add a line here with every new file.\n\n## Fonts\n\nSee [the logo](logo/a.svg).");
  assert.equal(
    html,
    '<p>Every file.</p>\n<h3 id="artwork-fonts">Fonts</h3>\n<p>See <a href="https://github.com/ncjsvr/OrielOS/blob/main/artwork/logo/a.svg">the logo</a>.</p>',
  );
});
