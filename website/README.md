# website

The orielos.org website: a single page written in plain HTML and CSS, with no JavaScript in the browser.

Contains:

- `public/`: the page template (`index.html`), the styles, the fonts, the icons, the not-found page, `robots.txt` and `.well-known/security.txt`.
- `build.mjs`: builds the site into `_site/`. It copies `public/` and the artwork the site shares with the OS (the logo, the Daybreak and Nightfall wallpapers and the Start icon) from `artwork/`, and fills in the contributors list and the latest release from GitHub's API.
- `test/`: tests for the build.

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

## Publishing

`.github/workflows/website.yml` builds and publishes the site to GitHub Pages on every push to `main`, whenever a release is published, and once a day. It doesn't publish until GitHub Pages is turned on for the repository, with GitHub Actions as its source. Pull requests that change the site or the artwork run the tests and an offline build, and never publish.

GitHub Pages can't set response headers, so the page sets its Content-Security-Policy and referrer policy in `<meta>` tags. The other security headers and HSTS come from Cloudflare, which sits in front of orielos.org.

## Writing and design

- Write in British English, in sentence case, and describe OrielOS as a familiar desktop tuned for gaming and development. Name Windows only for plain compatibility facts.
- Colours, type and shapes follow the OrielOS brand: Noto Sans for text and Noto Sans Display for headings, Oriel Blue for actions, and Daylight, the warm amber, used once.
- Use no Microsoft logos, fonts, icons or product names in the design.

## Credits

The fonts are Noto Sans and Noto Sans Display (Latin subset, from Fontsource 5.3.0), under the SIL Open Font License; see `public/fonts/OFL.txt`. The artwork is CC BY-SA 4.0, like the rest of `artwork/`.
