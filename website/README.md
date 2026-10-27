# website

The orielos.org website: a small set of pages written in plain HTML, CSS and Markdown, with no JavaScript in the browser, no cookies and no analytics.

Contains:

- `public/`: the home page (`index.html`), the not-found page (`404.html`), the styles, the fonts, the icons, the images and screenshots, `robots.txt`, `llms.txt` (a plain-text summary for AI tools), the IndexNow key file (the `.txt` file named by 32 hexadecimal characters) and `.well-known/security.txt`. Everything here is published as it is, apart from the two pages, which the build fills in.
- `templates/`: the parts every page shares. `header.html` is the logo and the main navigation, `footer.html` the footer, and `page.html` the whole document around every page but the home page and the not-found page. They aren't published on their own.
- `pages/`: pages with their own address, one file each, such as the download page, the credits and the press kit.
- `news/`: the news posts, in Markdown.
- `build.mjs`: builds the site into `_site/`. It copies `public/` and the artwork the site shares with the OS (the logo, the Daybreak and Nightfall wallpapers and the Start icon) from `artwork/`, builds every page, fills in the contributors list and the releases from GitHub, writes the news feed, checks every page for search engines and writes the sitemap.
- `pages.mjs`: the layout and every kind of page: guides, news, release notes and the pages in `pages/`.
- `markdown.mjs`: the Markdown renderer for the guides, the news, the release notes and the artwork credits.
- `indexnow.mjs`: tells search engines which pages a deploy changed.
- `test/`: tests for the renderer, the pages, a whole offline build and the IndexNow step.

## Building and previewing

You need Node.js 22. The site has no dependencies to install. From the repository root:

```bash
node website/build.mjs --offline
python3 -m http.server --directory website/_site 8000
```

Then open http://localhost:8000. `--offline` skips GitHub, so the site shows no contributors, no release and no release notes. Without it, the build reads GitHub's API and downloads the contributors' avatars; set `GITHUB_TOKEN` to a token of your own if you hit GitHub's rate limit.

Run the tests with:

```bash
node --test "website/test/*.test.mjs"
```

## The pages

| Address | Made from |
|---|---|
| `/` | `public/index.html` |
| `/download/` | `pages/download.html` |
| `/faq/` | `pages/faq.html` |
| `/guides/` and `/guides/<name>/` | the user docs in `docs/` at the repository root |
| `/news/`, `/news/<name>/` and `/news/feed.xml` | the posts in `news/`, and the releases |
| `/releases/` | the releases on GitHub |
| `/credits/` | `pages/credits.html`, with `artwork/CREDITS.md` |
| `/<name>/` | any other file in `pages/`, such as `pages/press.html` for `/press/` |
| `/404.html` | `public/404.html` |

Every page has the same header, footer, Content-Security-Policy and link to the news feed. Links and files on every page start with `/`, because the site is served from the root of orielos.org. The navigation marks the section a page belongs to (Download, Guides or News) with `aria-current="page"`.

### Guides

Every `docs/*.md` but `README.md` becomes a guide at `/guides/<file name without .md>/`. The docs are also published as the repository's wiki, so they stay plain Markdown with nothing added for the site:

- The page's title and heading come from the file's first `# ` heading, and its description from the first paragraph, cut to about 155 characters.
- Links to other docs go to their guides, a link to `README.md` goes to `/guides/`, and links to any other file in the repository go to it on GitHub. The "Licence:" line at the end of a doc is left out; each guide says its licence and links to the file on GitHub instead.
- Pictures go in `docs/images/` and are linked from the docs as `images/<file>`. The build publishes them at `/guides/images/` and gives PNG and WebP pictures their width and height.
- `/guides/` lists the guides in groups, in the order set by `GUIDE_GROUPS` in `pages.mjs`, with the one-line descriptions from `docs/README.md`. A guide that isn't in a group goes under "More", so a new doc is never missed. Each guide links to the one before and after it in that order.
- "Find a topic", at the end of `/guides/`, lists every `##` and `###` heading in the guides from A to Z, each linked to its place. It is the site's search: the site runs no JavaScript and uses no search service, and a browser's own find (Ctrl+F) searches the list.

### News

Each post is a Markdown file in `news/`, and its file name is its address: `news/first-installer.md` becomes `/news/first-installer/`. File names use lower-case letters, digits and hyphens. A post starts with front matter, one `key: value` per line between `---` lines:

```markdown
---
title: The first installer is out
date: 2026-10-27
summary: One or two sentences for the news list, link previews and search results.
image: /images/screenshots/start.webp
image_alt: What the picture shows, for people who can't see it
image_width: 1280
image_height: 800
---

The post, in Markdown.
```

- `title` (at most 70 characters), `date` (YYYY-MM-DD) and `summary` (at most 160 characters) are required.
- `image` is optional: a file under `public/`, shown under the date and used for the post's link preview. It needs `image_alt`. `image_width` and `image_height` are optional, in pixels.

The build stops with the file's name and what's wrong if a field is missing or invalid, a picture doesn't exist, or two posts would share an address. `/news/` lists the posts newest first, and the home page shows the newest three in its News section, which is left out while there are none.

`/news/feed.xml` is an Atom feed of every post and every release, newest first, with each one's full text. Every page links to it, so feed readers find it from any address on the site.

### Release notes

`/releases/` shows the last 30 full releases from GitHub (drafts and pre-releases are left out), newest first, each with its notes, its date and a link to it on GitHub. Each release has its tag as its anchor, so `/releases/#v0.0.7` links to one. Relative links in the notes go to the files on GitHub. Offline, or before the first release, the page says there are no releases yet.

### Pages in `pages/`

Each `pages/<name>.html` or `pages/<name>.md` becomes `/<name>/`. It starts with front matter like a news post's:

- `title`: the page's `<title>`, at most 70 characters.
- `heading`: the page's `<h1>`, if it differs from the title.
- `description`: for search results and link previews, at most 160 characters.
- `image` and `image_alt`, with `image_width` and `image_height`: optional, for the link preview.

An HTML page's body is the HTML inside `<main>`, after the heading, and can use the same markers as the home page. A Markdown page's body is rendered like a guide.

## How the pages are filled in

The page files mark the parts the build fills in with comments:

- `<!-- include:header -->` and `<!-- include:footer -->`: the shared header and footer, from `templates/`.
- `<!-- if:release -->` and `<!-- if:no-release -->`: whether a release has been published.
- `<!-- if:iso -->` and `<!-- if:no-iso -->`: whether the latest release has an installer ISO.
- `<!-- if:sha256 -->` and `<!-- if:no-sha256 -->`: whether GitHub has a SHA-256 checksum for the installer.
- `<!-- if:sums -->` and `<!-- if:no-sums -->`: whether the latest release has a `SHA256SUMS` file.
- `<!-- if:contributors -->` and `<!-- if:no-contributors -->`: whether the contributors list could be read.
- `<!-- if:news -->` and `<!-- if:no-news -->`: whether there are news posts.
- `<!-- contributors -->` is replaced by the contributors list, `<!-- news -->` by the three newest posts, and `<!-- artwork-credits -->` by `artwork/CREDITS.md`.
- `{{release.name}}`, `{{release.version}}`, `{{release.url}}`, `{{iso.url}}`, `{{iso.size}}`, `{{iso.sha256}}` and `{{sums.url}}` are replaced by the release's details. `{{release.version}}` is the release's tag, such as `v0.0.7`, and only when that tag is a plain version. The home page's description and its software structured data use it, so the version isn't written out in several places.

The build stops if a marker is left over. The download is the first `.iso` file attached to the newest full release on GitHub, and `SHA256SUMS` is the release's file of that exact name. Pre-releases are left out. The SHA-256 checksum is the one GitHub records for the file.

## Markdown

`markdown.mjs` renders the Markdown the docs, the CHANGELOG and the release notes use: `#` to `####` headings with GitHub's anchors (so links such as `install.md#make-room-next-to-windows` work), paragraphs, bold, emphasis, code, links, `<https://…>` links, pictures, lists nested by indentation, fenced code blocks, quotes, horizontal rules and tables.

Everything in it is shown as text: HTML written in the Markdown is escaped, never passed through. Links keep only `http:`, `https:` and `mailto:` addresses, `#` anchors and relative paths; anything else, such as `javascript:`, shows as plain text. Every picture needs alt text, or the build stops. Pictures from other sites become links, so the site never loads anything from another site. A paragraph that is only a picture becomes a figure.

## Search engines

The build fails unless every page that search engines may index (all but those marked `noindex`, such as the not-found page) has:

- one `<title>` of at most 70 characters and a `<meta name="description">` of at most 160;
- a canonical link, and an `og:url`, both equal to the page's own address (`https://orielos.org/` for `index.html`, `https://orielos.org/news/` for `news/index.html`);
- `og:title`, `og:description`, `og:image` (on orielos.org), `og:image:width`, `og:image:height` and `og:image:alt`, for link previews (the width and height are left out when a picture has no size);
- `twitter:site` set to `@BuiltByNath`;
- a title, description and address that no other page shares.

Script blocks must be `application/ld+json` structured data that parses as JSON; anything that would run in the browser fails the build. The home page's structured data names the site and the OrielOS organisation, with its logo and its GitHub and Discord pages, and describes OrielOS itself as software: an operating system, GPL-3.0, free, with the current release's version when there is one. The FAQ page lists its questions the same way. Each news post describes itself as a blog post by that organisation.

Every `<img>` needs alt text, even decorative ones inside parts hidden from screen readers, because search engines read it and SEO checkers flag empty `alt`. A contributor's avatar reads "<name>’s avatar", so it doesn't just repeat the name beside it.

The "Share OrielOS" links are plain links to each site's own share page (X, Bluesky, Reddit, Facebook) and a `mailto:` link, so nothing is loaded from those sites unless a visitor clicks one.

The build then writes `sitemap.xml` with every checked page. When git can see the commit that last changed a page's source (the page itself, and the header, footer and layout it uses), the entry includes that date as `lastmod`, `YYYY-MM-DD`. The release notes also use the newest release's publish date when that is later. A shallow checkout only knows the commits it has, so a page whose files aren't in those commits is listed without a date, rather than with one guessed from the checkout time. `robots.txt` lets every crawler in and points to the sitemap.

## Publishing

`.github/workflows/website.yml` builds and publishes the site to GitHub Pages on every push to `main`, whenever a release is published, and once a day. It doesn't publish until GitHub Pages is turned on for the repository, with GitHub Actions as its source. Pull requests that change the site, the artwork, the docs or the CHANGELOG run the tests and an offline build, and never publish.

Before each deploy, `node website/indexnow.mjs changed` compares the built pages with the live site and lists the new, changed and removed ones. After the deploy, `node website/indexnow.mjs submit` sends that list to [IndexNow](https://www.indexnow.org/), which shares it with the search engines that take part, so they crawl the pages soon. The key in the key file is public by design: search engines fetch it to check that the list comes from orielos.org. Network problems in either step only print a warning, so they never stop a deploy.

GitHub Pages can't set response headers, so every page sets its Content-Security-Policy and referrer policy in `<meta>` tags. GitHub Pages enforces HTTPS, and the site sends no other security headers.

The policy allows one thing from another site: images from `https://www.bestpractices.dev`, for the OpenSSF Best Practices and Baseline badges in the footer. The badges are loaded live, so they always show the project's current levels, and that site sets no cookies. Everything else comes from orielos.org. The policy's `connect-src 'self'` lets tools that audit the page from inside it, such as Lighthouse, read `robots.txt`; no script can run on the page, so nothing else can use it.

## Writing and design

- Write in British English, in sentence case, and describe OrielOS as a free, open-source Linux desktop for gaming and development. Name Windows only for plain compatibility facts.
- Colours, type and shapes follow the OrielOS brand: Noto Sans for text and Noto Sans Display for headings, Oriel Blue for actions, and Daylight, the warm amber, used once.
- The styles for the inner pages are at the end of `styles.css` and use the same colours, spacing and shapes. Every page works at 375 pixels wide and in light and dark mode; code and tables scroll inside their own box.
- Use no Microsoft logos, fonts, icons or product names in the design.

## Credits

The fonts are Noto Sans and Noto Sans Display (Latin subset, from Fontsource 5.3.0), under the SIL Open Font License; see `public/fonts/OFL.txt`. The artwork is CC BY-SA 4.0, like the rest of `artwork/`. The full credits are at https://orielos.org/credits/.
