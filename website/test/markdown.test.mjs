// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import test from "node:test";

import {
  imageDimensions,
  isSafeUrl,
  renderMarkdown,
  renderMarkdownDocument,
  renderMarkdownInline,
  slugify,
} from "../markdown.mjs";

const md = (source, options) => renderMarkdown(source, options);

test("headings get GitHub-style ids, with numbers for duplicates", () => {
  const { html, headings } = renderMarkdownDocument(
    "# Install OrielOS\n\n## Make room next to Windows\n\n## What you'll need\n\n### 3a. Start it in QEMU\n\n#### Deep\n\n## What you'll need\n\n## What you'll need\n",
  );
  assert.match(html, /<h1 id="install-orielos">Install OrielOS<\/h1>/);
  assert.match(html, /<h2 id="make-room-next-to-windows">/);
  assert.match(html, /<h3 id="3a-start-it-in-qemu">3a\. Start it in QEMU<\/h3>/);
  assert.match(html, /<h4 id="deep">Deep<\/h4>/);
  assert.deepEqual(
    headings.filter((heading) => heading.text === "What you'll need").map((heading) => heading.id),
    ["what-youll-need", "what-youll-need-1", "what-youll-need-2"],
  );
  assert.deepEqual(headings[0], { level: 1, sourceLevel: 1, text: "Install OrielOS", id: "install-orielos" });
});

test("slugify drops punctuation and keeps letters, digits, hyphens and underscores", () => {
  assert.equal(slugify("Settings → Privacy & security"), "settings--privacy--security");
  assert.equal(slugify("Wi-Fi and snake_case"), "wi-fi-and-snake_case");
  assert.equal(slugify("Café déjà vu"), "café-déjà-vu");
  assert.equal(slugify("`code` and **bold**"), "code-and-bold");
});

test("heading ids come from the text, not the Markdown", () => {
  const { headings } = renderMarkdownDocument("## Using `orielos-update` **now**\n");
  assert.equal(headings[0].id, "using-orielos-update-now");
});

test("headings can be shifted and prefixed", () => {
  const html = md("## Added\n\n### Detail\n", { topHeadingLevel: 3, idPrefix: "v1-" });
  assert.match(html, /<h3 id="v1-added">Added<\/h3>/);
  assert.match(html, /<h4 id="v1-detail">Detail<\/h4>/);
});

test("paragraphs join hard-wrapped lines", () => {
  assert.equal(md("One line\nand the next.\n\nA second paragraph."), "<p>One line\nand the next.</p>\n<p>A second paragraph.</p>");
});

test("inline formatting: bold, emphasis, code, links and autolinks", () => {
  const html = md(
    "**Bold**, *em*, _em too_, `code <b>`, [a link](https://example.com/a?b=1&c=2 \"Title\") and <https://aka.ms/x>.",
  );
  assert.equal(
    html,
    '<p><strong>Bold</strong>, <em>em</em>, <em>em too</em>, <code>code &lt;b&gt;</code>, ' +
      '<a href="https://example.com/a?b=1&amp;c=2" title="Title">a link</a> and <a href="https://aka.ms/x">https://aka.ms/x</a>.</p>',
  );
});

test("underscores inside words and lone stars stay as they are", () => {
  assert.equal(md("hid_xpadneo and xone_gip, 2 * 3 * 4"), "<p>hid_xpadneo and xone_gip, 2 * 3 * 4</p>");
  assert.equal(md("**Settings > Bluetooth & devices**"), "<p><strong>Settings &gt; Bluetooth &amp; devices</strong></p>");
});

test("bare URLs stay as text and backslash escapes work", () => {
  assert.equal(md("See https://example.com and \\*not em\\*."), "<p>See https://example.com and *not em*.</p>");
});

test("code spans with double backticks", () => {
  assert.equal(md("``a ` b``"), "<p><code>a ` b</code></p>");
});

test("raw HTML is escaped, never passed through", () => {
  const html = md('<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>\n\nText with <b>tags</b> & "quotes".');
  assert.doesNotMatch(html, /<script|<img|<b>/i);
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.match(html, /&lt;b&gt;tags&lt;\/b&gt; &amp; &quot;quotes&quot;/);
});

test("javascript: and other unsafe links render as plain text", () => {
  for (const href of ["javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,x", "vbscript:x", "<javascript:alert(1)>"]) {
    const html = md(`[click](${href})`);
    assert.equal(html, "<p>click</p>", href);
  }
  // Browsers drop tabs inside addresses, so this mustn't become a link either.
  assert.doesNotMatch(md("[click](java\tscript:alert(1))"), /<a\b/);
  assert.equal(md("<javascript:alert(1)>"), "<p>&lt;javascript:alert(1)&gt;</p>");
  assert.equal(isSafeUrl("javascript:alert(1)"), false);
  assert.equal(isSafeUrl(" https://example.com"), false);
  assert.equal(isSafeUrl("https://example.com"), true);
  assert.equal(isSafeUrl("mailto:hello@orielos.org"), true);
  assert.equal(isSafeUrl("#section"), true);
  assert.equal(isSafeUrl("../CONTRIBUTING.md"), true);
  assert.equal(isSafeUrl("/guides/"), true);
});

test("link addresses and titles are escaped", () => {
  const html = md('[x](https://example.com/"onmouseover="alert(1) "a\\"b")');
  assert.doesNotMatch(html, /href="[^"]*"onmouseover/);
  assert.equal(md("[x](<https://example.com/a b>)"), "<p>x</p>");
  assert.equal(md('[x](https://e.com "say <hi>")'), '<p><a href="https://e.com" title="say &lt;hi&gt;">x</a></p>');
});

test("rewriteLink rewrites link addresses", () => {
  const html = md("[Other](other.md#x) and [web](https://example.com)", {
    rewriteLink: (href) => (href.startsWith("http") ? href : `/guides/${href.replace(".md", "/")}`),
  });
  assert.equal(html, '<p><a href="/guides/other/#x">Other</a> and <a href="https://example.com">web</a></p>');
});

test("a rewritten address must still be safe", () => {
  assert.equal(md("[x](y.md)", { rewriteLink: () => "javascript:alert(1)" }), "<p>x</p>");
});

test("unordered and ordered lists, nested by indentation", () => {
  const source = [
    "1. Choose your **language**.",
    "2. On the summary screen:",
    "   - **Network**: connect.",
    "   - **Installation Destination**: select your drive.",
    "     - **Next to Windows**: keep Automatic.",
    "     - **Whole drive**: delete all.",
    "3. Begin.",
    "",
    "- One",
    "  - Nested by two spaces",
    "* Star",
  ].join("\n");
  const html = md(source);
  assert.equal(
    html,
    [
      "<ol>",
      "<li>Choose your <strong>language</strong>.</li>",
      "<li>On the summary screen:",
      "<ul>",
      "<li><strong>Network</strong>: connect.</li>",
      "<li><strong>Installation Destination</strong>: select your drive.",
      "<ul>",
      "<li><strong>Next to Windows</strong>: keep Automatic.</li>",
      "<li><strong>Whole drive</strong>: delete all.</li>",
      "</ul></li>",
      "</ul></li>",
      "<li>Begin.</li>",
      "</ol>",
      "<ul>",
      "<li>One",
      "<ul>",
      "<li>Nested by two spaces</li>",
      "</ul></li>",
      "</ul>",
      "<ul>",
      "<li>Star</li>",
      "</ul>",
    ].join("\n"),
  );
});

test("ordered lists keep their start number", () => {
  assert.match(md("3. Three\n4. Four"), /^<ol start="3">/);
});

test("list items with several paragraphs make a loose list", () => {
  const html = md("- First paragraph.\n\n  Second paragraph.\n- Next item.");
  assert.equal(html, "<ul>\n<li><p>First paragraph.</p>\n<p>Second paragraph.</p></li>\n<li><p>Next item.</p></li>\n</ul>");
});

test("a lazy line continues a list item's paragraph", () => {
  assert.equal(md("- One\ncontinued\n- Two"), "<ul>\n<li>One\ncontinued</li>\n<li>Two</li>\n</ul>");
});

test("a list ends at a paragraph after a blank line", () => {
  assert.equal(md("- One\n\nAfter."), "<ul>\n<li>One</li>\n</ul>\n<p>After.</p>");
});

test("fenced code blocks are escaped and keep their language", () => {
  const html = md("Run:\n\n```sh\nsudo orielos-update stage <file> && echo \"done\"\n    indented\n```\n\nAfter.");
  assert.equal(
    html,
    '<p>Run:</p>\n<pre><code class="language-sh">sudo orielos-update stage &lt;file&gt; &amp;&amp; echo &quot;done&quot;\n    indented</code></pre>\n<p>After.</p>',
  );
});

test("fenced code inside a list item", () => {
  const html = md("1. Run this:\n\n   ```sh\n   ls -l\n   ```\n2. Done.");
  assert.match(html, /<li><p>Run this:<\/p>\n<pre><code class="language-sh">ls -l<\/code><\/pre><\/li>/);
});

test("a code block's Markdown isn't rendered", () => {
  assert.equal(md("```\n**not bold** [x](javascript:y)\n```"), "<pre><code>**not bold** [x](javascript:y)</code></pre>");
});

test("block quotes, rules and tables", () => {
  assert.equal(md("> Quoted **text**\n> on two lines.\n\n---\n\n***"), "<blockquote>\n<p>Quoted <strong>text</strong>\non two lines.</p>\n</blockquote>\n<hr>\n<hr>");
  const table = md("| Shortcut | What it does |\n|---|:---:|\n| Windows + E | Opens `Files` |\n| A \\| B | <b> |\n");
  assert.equal(
    table,
    [
      '<div class="table-wrap">',
      "<table>",
      "<thead>",
      '<tr><th>Shortcut</th><th class="align-center">What it does</th></tr>',
      "</thead>",
      "<tbody>",
      '<tr><td>Windows + E</td><td class="align-center">Opens <code>Files</code></td></tr>',
      '<tr><td>A | B</td><td class="align-center">&lt;b&gt;</td></tr>',
      "</tbody>",
      "</table>",
      "</div>",
    ].join("\n"),
  );
});

test("a table follows a paragraph without a blank line", () => {
  assert.match(md("Intro:\n| a | b |\n|---|---|\n| 1 | 2 |"), /<p>Intro:<\/p>\n<div class="table-wrap">/);
});

test("pipes inside code spans don't split table cells", () => {
  assert.match(md("| a | b |\n|---|---|\n| `x | y` | z |"), /<td><code>x \| y<\/code><\/td><td>z<\/td>/);
});

test("images: alt text required, local images only, a lone image becomes a figure", () => {
  assert.equal(
    md("![The Start menu](images/start.png)", { rewriteImage: (src) => `/guides/${src}` }),
    '<figure class="doc-image"><img src="/guides/images/start.png" alt="The Start menu" loading="lazy" decoding="async"></figure>',
  );
  assert.equal(
    md('Inline ![A "quote" & more](/x.png) image.'),
    '<p>Inline <img src="/x.png" alt="A &quot;quote&quot; &amp; more" loading="lazy" decoding="async"> image.</p>',
  );
  assert.throws(() => md("![](images/start.png)"), /an image has no alt text: images\/start\.png/);
  assert.throws(() => md("![  ](images/start.png)"), /no alt text/);
  // Images on other sites would be a third-party request, so they become links.
  assert.equal(md("![Logo](https://example.com/logo.png)"), '<p><a href="https://example.com/logo.png">Logo</a></p>');
  assert.equal(md("![Logo](javascript:alert(1))"), "<p>Logo</p>");
  assert.equal(md("![](https://example.com/x.png)", { requireAlt: false }), '<p><a href="https://example.com/x.png">https://example.com/x.png</a></p>');
});

test("images get their size when it is known", () => {
  const html = md("![Shot](/a.png) ![Other](/b.png)", {
    imageSize: (src) => (src === "/a.png" ? { width: 1280, height: 800 } : null),
  });
  assert.match(html, /<img src="\/a\.png" alt="Shot" width="1280" height="800" loading="lazy" decoding="async">/);
  assert.match(html, /<img src="\/b\.png" alt="Other" loading="lazy" decoding="async">/);
});

test("imageDimensions reads PNG and WebP headers", () => {
  const png = Buffer.alloc(24);
  png.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0);
  png.write("IHDR", 12, "ascii");
  png.writeUInt32BE(1280, 16);
  png.writeUInt32BE(800, 20);
  assert.deepEqual(imageDimensions(png), { width: 1280, height: 800 });

  const webp = (chunk, fill) => {
    const bytes = Buffer.alloc(32);
    bytes.write("RIFF", 0, "ascii");
    bytes.write("WEBP", 8, "ascii");
    bytes.write(chunk, 12, "ascii");
    fill(bytes);
    return bytes;
  };
  const lossy = webp("VP8 ", (bytes) => {
    bytes.set([0x9d, 0x01, 0x2a], 23);
    bytes.writeUInt16LE(1280, 26);
    bytes.writeUInt16LE(720, 28);
  });
  assert.deepEqual(imageDimensions(lossy), { width: 1280, height: 720 });
  const lossless = webp("VP8L", (bytes) => {
    bytes[20] = 0x2f;
    bytes.writeUInt32LE((1280 - 1) | ((800 - 1) << 14), 21);
  });
  assert.deepEqual(imageDimensions(lossless), { width: 1280, height: 800 });
  const extended = webp("VP8X", (bytes) => {
    bytes.writeUIntLE(1280 - 1, 24, 3);
    bytes.writeUIntLE(800 - 1, 27, 3);
  });
  assert.deepEqual(imageDimensions(extended), { width: 1280, height: 800 });
  assert.equal(imageDimensions(Buffer.from("not an image")), null);
});

test("the first paragraph's plain text", () => {
  const { firstParagraph } = renderMarkdownDocument("# Title\n\n![A picture](/a.png)\n\nThe **first** [paragraph](x.md)\nwraps.\n\nSecond.");
  assert.equal(firstParagraph, "The first paragraph wraps.");
});

test("Windows line endings and tabs", () => {
  assert.equal(md("# Title\r\n\r\n-\tOne\r\n-\tTwo\r\n"), '<h1 id="title">Title</h1>\n<ul>\n<li>One</li>\n<li>Two</li>\n</ul>');
});

test("renderMarkdownInline renders one line without a paragraph", () => {
  assert.equal(renderMarkdownInline("the **Store** & <apps>"), "the <strong>Store</strong> &amp; &lt;apps&gt;");
});
