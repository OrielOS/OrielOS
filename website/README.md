# website

The orielos.org website: a single page written in plain HTML and CSS, with no JavaScript in the browser, no cookies and no analytics.

Contains:

- `public/`: the page template (`index.html`), the styles, the fonts, the icons, the not-found page, `robots.txt`, `llms.txt` (a plain-text summary for AI tools), the IndexNow key file (the `.txt` file named by 32 hexadecimal characters) and `.well-known/security.txt`.
- `build.mjs`: builds the site into `_site/`. It copies `public/` and the artwork the site shares with the OS (the logo, the Daybreak and Nightfall wallpapers and the Start icon) from `artwork/`, fills in the contributors list and the latest release from GitHub's API, checks every page for search engines and writes the sitemap.
- `indexnow.mjs`: tells search engines which pages a deploy changed.
- `test/`: tests for the build and the IndexNow step.

## Building and previewing

You need Node.js 22. From the repository root:

```bash
node website/build.mjs --offline
python3 -m http.server --directory website/_site 8000
```

Then open http://localhost:8000. `--offline` skips GitHub, so the page shows no contributors and no release. Without it, the build reads GitHub's API and downloads the contributors' avatars; set `GITHUB_TOKEN` to a token of your own if you hit GitHub's rate limit.

Run the tests with:

```bash
node --test "website/test/*.test.mjs"
```

## How the page is filled in

`index.html` marks the parts that depend on GitHub with comments, which the build keeps or removes:

- `<!-- if:release -->` and `<!-- if:no-release -->`: whether a release has been published.
- `<!-- if:iso -->` and `<!-- if:no-iso -->`: whether the latest release has an installer ISO.
- `<!-- if:contributors -->` and `<!-- if:no-contributors -->`: whether the contributors list could be read.
- `<!-- contributors -->` is replaced by the list, and `{{release.name}}`, `{{release.url}}`, `{{iso.url}}`, `{{iso.size}}` and `{{iso.sha256}}` by the release's details.

The download is the first `.iso` file attached to the newest full release on GitHub. Pre-releases are left out. The SHA-256 checksum is the one GitHub records for the file.

## Search engines

The build fails unless every page that search engines may index (all but those marked `noindex`, such as the not-found page) has:

- one `<title>` of at most 70 characters and a `<meta name="description">` of at most 160;
- a canonical link, and an `og:url`, both equal to the page's own address (`https://orielos.org/` for `index.html`, `https://orielos.org/news/` for `news/index.html`);
- `og:title`, `og:description`, `og:image` (on orielos.org) and `og:image:alt`, for link previews;
- a title, description and address that no other page shares.

Script blocks must be `application/ld+json` structured data that parses as JSON; anything that would run in the browser fails the build. The home page's structured data names the site and the OrielOS organisation, with its logo and its GitHub and Discord pages.

Every `<img>` needs alt text, even decorative ones inside parts hidden from screen readers, because search engines read it and SEO checkers flag empty `alt`. A contributor's avatar reads "<name>’s avatar", so it doesn't just repeat the name beside it.

The "Share OrielOS" links are plain links to each site's own share page (X, Bluesky, Reddit, Facebook) and a `mailto:` link, so nothing is loaded from those sites unless a visitor clicks one.

The build then writes `sitemap.xml` with every checked page. It has no `lastmod` dates, because a shallow checkout can't give accurate ones. `robots.txt` lets every crawler in and points to the sitemap.

## Publishing

`.github/workflows/website.yml` builds and publishes the site to GitHub Pages on every push to `main`, whenever a release is published, and once a day. It doesn't publish until GitHub Pages is turned on for the repository, with GitHub Actions as its source. Pull requests that change the site or the artwork run the tests and an offline build, and never publish.

Before each deploy, `node website/indexnow.mjs changed` compares the built pages with the live site and lists the new, changed and removed ones. After the deploy, `node website/indexnow.mjs submit` sends that list to [IndexNow](https://www.indexnow.org/), which shares it with the search engines that take part, so they crawl the pages soon. The key in the key file is public by design: search engines fetch it to check that the list comes from orielos.org. Network problems in either step only print a warning, so they never stop a deploy.

GitHub Pages can't set response headers, so the page sets its Content-Security-Policy and referrer policy in `<meta>` tags. GitHub Pages enforces HTTPS, and the site sends no other security headers.

The policy allows one thing from another site: images from `https://www.bestpractices.dev`, for the OpenSSF Best Practices badge in the footer. The badge is loaded live, so it always shows the project's current level, and that site sets no cookies. Everything else comes from orielos.org. The policy's `connect-src 'self'` lets tools that audit the page from inside it, such as Lighthouse, read `robots.txt`; no script can run on the page, so nothing else can use it.

## Writing and design

- Write in British English, in sentence case, and describe OrielOS as a familiar desktop tuned for gaming and development. Name Windows only for plain compatibility facts.
- Colours, type and shapes follow the OrielOS brand: Noto Sans for text and Noto Sans Display for headings, Oriel Blue for actions, and Daylight, the warm amber, used once.
- Use no Microsoft logos, fonts, icons or product names in the design.

## Credits

The fonts are Noto Sans and Noto Sans Display (Latin subset, from Fontsource 5.3.0), under the SIL Open Font License; see `public/fonts/OFL.txt`. The artwork is CC BY-SA 4.0, like the rest of `artwork/`.
