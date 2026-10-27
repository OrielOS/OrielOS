// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// A small Markdown renderer for the website, with no dependencies.
//
// It covers what the user docs, the CHANGELOG, the artwork credits and the
// release notes use: ATX headings with GitHub-style ids, paragraphs, bold,
// emphasis, code spans, links, autolinks, images on this site, nested lists,
// fenced code blocks, block quotes, horizontal rules and pipe tables.
//
// Everything is escaped. Raw HTML in the source shows as text, and links
// keep only http:, https: and mailto: addresses, fragments and relative paths;
// anything else, such as javascript:, renders as plain text.

const ENTITIES = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'" };

export function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function decodeEntities(value) {
  return String(value).replace(/&(?:amp|lt|gt|quot|#39);/g, (entity) => ENTITIES[entity]);
}

// The text of some HTML, without its tags. Any stray angle bracket goes too, so
// nothing tag-like survives before the entities are decoded; callers escape the
// result again wherever it goes back into HTML.
export function htmlToText(html) {
  return decodeEntities(String(html).replace(/<[^>]*>/g, "").replace(/[<>]/g, ""));
}

// GitHub's heading anchors: lower case, punctuation dropped, spaces to hyphens.
export function slugify(text) {
  return String(text)
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{M}\p{N}\p{Pc} -]/gu, "")
    .replaceAll(" ", "-");
}

// Only addresses that can't run anything: web and mail links, fragments and
// relative paths. Browsers drop tabs and line breaks inside addresses, so any
// whitespace or control character makes the address unsafe.
export function isSafeUrl(url) {
  const value = String(url);
  if (value === "" || /[\u0000- \u007f]/.test(value)) return false;
  const scheme = /^([a-zA-Z][a-zA-Z0-9+.-]*):/.exec(value);
  if (!scheme) return !value.startsWith("\\");
  return ["http", "https", "mailto"].includes(scheme[1].toLowerCase());
}

function isSameSite(url) {
  return !/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(url) && !url.startsWith("//");
}

const PUNCTUATION = /[!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~]/;

// ---------------------------------------------------------------------------
// Blocks

const FENCE = /^( {0,3})(`{3,}|~{3,})\s*([^`\s]*)[^`]*$/;
const HEADING = /^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$/;
const RULE = /^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$/;
const QUOTE = /^ {0,3}>/;
const LIST = /^( {0,3})([-*+]|(\d{1,9})[.)])([ \t]+|$)/;
const TABLE_DELIMITER = /^ {0,3}\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$/;

const isBlank = (line) => /^[ \t]*$/.test(line);
const indentOf = (line) => /^ */.exec(line)[0].length;

function expandTabs(line) {
  return line.replace(/^[ \t]+/, (lead) => {
    let width = 0;
    for (const char of lead) width = char === "\t" ? width + 4 - (width % 4) : width + 1;
    return " ".repeat(width);
  });
}

function listMarker(line) {
  const match = LIST.exec(line);
  if (!match) return null;
  const indent = match[1].length;
  const width = match[2].length;
  const spaces = match[4].length;
  const contentIndent = indent + width + (spaces >= 1 && spaces <= 4 ? spaces : 1);
  return {
    ordered: match[3] !== undefined,
    bullet: match[3] === undefined ? match[2] : match[2].slice(-1),
    start: match[3] === undefined ? null : Number(match[3]),
    indent,
    contentIndent,
    content: spaces > 4 ? line.slice(indent + width + 1) : line.slice(match[0].length),
  };
}

function isTableStart(lines, index) {
  return (
    index + 1 < lines.length &&
    lines[index].includes("|") &&
    TABLE_DELIMITER.test(lines[index + 1]) &&
    lines[index + 1].includes("-") &&
    (lines[index + 1].includes("|") || /^\s*\|/.test(lines[index]))
  );
}

function startsBlock(line) {
  return FENCE.test(line) || HEADING.test(line) || RULE.test(line) || QUOTE.test(line) || listMarker(line) !== null;
}

// Splits a table row on the pipes that aren't escaped or inside code.
function tableCells(line) {
  let row = line.trim();
  if (row.startsWith("|")) row = row.slice(1);
  if (row.endsWith("|") && !row.endsWith("\\|")) row = row.slice(0, -1);
  const cells = [];
  let cell = "";
  let ticks = 0;
  for (let index = 0; index < row.length; index += 1) {
    const char = row[index];
    if (char === "\\" && row[index + 1] === "|") {
      cell += "|";
      index += 1;
    } else if (char === "`") {
      let run = 0;
      while (row[index + run] === "`") run += 1;
      ticks = ticks === 0 ? run : ticks === run ? 0 : ticks;
      cell += "`".repeat(run);
      index += run - 1;
    } else if (char === "|" && ticks === 0) {
      cells.push(cell.trim());
      cell = "";
    } else {
      cell += char;
    }
  }
  cells.push(cell.trim());
  return cells;
}

function parseBlocks(lines) {
  const blocks = [];
  let index = 0;
  let blankBefore = false;
  const add = (block) => {
    block.blankBefore = blankBefore;
    blankBefore = false;
    blocks.push(block);
  };

  while (index < lines.length) {
    const line = lines[index];
    if (isBlank(line)) {
      blankBefore = true;
      index += 1;
      continue;
    }

    const fence = FENCE.exec(line);
    if (fence) {
      const [, indent, marker, language] = fence;
      const body = [];
      index += 1;
      while (index < lines.length) {
        const close = /^ {0,3}(`{3,}|~{3,})[ \t]*$/.exec(lines[index]);
        if (close && close[1][0] === marker[0] && close[1].length >= marker.length) {
          index += 1;
          break;
        }
        body.push(lines[index].replace(new RegExp(`^ {0,${indent.length}}`), ""));
        index += 1;
      }
      add({ type: "code", language, text: body.join("\n") });
      continue;
    }

    const heading = HEADING.exec(line);
    if (heading) {
      add({ type: "heading", level: heading[1].length, text: heading[2] ?? "" });
      index += 1;
      continue;
    }

    if (RULE.test(line)) {
      add({ type: "rule" });
      index += 1;
      continue;
    }

    if (QUOTE.test(line)) {
      const inner = [];
      while (index < lines.length && QUOTE.test(lines[index])) {
        inner.push(lines[index].replace(/^ {0,3}> ?/, ""));
        index += 1;
      }
      add({ type: "quote", children: parseBlocks(inner) });
      continue;
    }

    if (isTableStart(lines, index)) {
      const header = tableCells(lines[index]);
      const align = tableCells(lines[index + 1]).map((cell) => {
        const left = cell.startsWith(":");
        const right = cell.endsWith(":");
        return left && right ? "center" : right ? "right" : left ? "left" : "";
      });
      const rows = [];
      index += 2;
      while (index < lines.length && !isBlank(lines[index]) && lines[index].includes("|")) {
        rows.push(tableCells(lines[index]));
        index += 1;
      }
      add({ type: "table", header, align, rows });
      continue;
    }

    const marker = listMarker(line);
    if (marker) {
      const before = blankBefore;
      blankBefore = false;
      const list = { type: "list", ordered: marker.ordered, start: marker.start, loose: false, items: [] };
      while (index < lines.length) {
        const item = listMarker(lines[index]);
        if (!item || item.ordered !== marker.ordered || item.bullet !== marker.bullet) break;
        const itemLines = [item.content];
        const threshold = Math.min(item.contentIndent, item.indent + 2);
        index += 1;
        while (index < lines.length) {
          const next = lines[index];
          if (isBlank(next)) {
            itemLines.push("");
          } else if (indentOf(next) >= threshold) {
            itemLines.push(next.slice(Math.min(indentOf(next), item.contentIndent)));
          } else if (!isBlank(itemLines.at(-1)) && !startsBlock(next) && !isTableStart(lines, index)) {
            // A paragraph's lazy continuation line.
            itemLines.push(next.trim());
          } else {
            break;
          }
          index += 1;
        }
        let trailing = 0;
        while (itemLines.length > 1 && isBlank(itemLines.at(-1))) {
          itemLines.pop();
          trailing += 1;
        }
        const children = parseBlocks(itemLines);
        if (children.some((child, position) => position > 0 && child.blankBefore)) list.loose = true;
        list.items.push(children);
        if (trailing > 0) {
          const following = index < lines.length ? listMarker(lines[index]) : null;
          if (following && following.ordered === marker.ordered && following.bullet === marker.bullet) {
            list.loose = true;
          } else {
            blankBefore = true;
            break;
          }
        }
      }
      const after = blankBefore;
      blankBefore = before;
      add(list);
      blankBefore = after;
      continue;
    }

    const paragraph = [line.trim()];
    index += 1;
    while (
      index < lines.length &&
      !isBlank(lines[index]) &&
      !startsBlock(lines[index]) &&
      !isTableStart(lines, index)
    ) {
      paragraph.push(lines[index].trim());
      index += 1;
    }
    add({ type: "paragraph", text: paragraph.join("\n") });
  }
  return blocks;
}

// ---------------------------------------------------------------------------
// Inline text

// The end of a run of `count` backticks that closes a code span, or -1.
function closingTicks(text, from, count) {
  for (let index = from; index < text.length; ) {
    if (text[index] !== "`") {
      index += 1;
      continue;
    }
    let run = 0;
    while (text[index + run] === "`") run += 1;
    if (run === count) return index;
    index += run;
  }
  return -1;
}

// A link or image starting at the "[" at `start`: its label, address, title
// and where it ends; null if the text there isn't one.
function parseLink(text, start) {
  let depth = 0;
  let close = -1;
  for (let index = start; index < text.length; index += 1) {
    const char = text[index];
    if (char === "\\") {
      index += 1;
    } else if (char === "`") {
      let run = 0;
      while (text[index + run] === "`") run += 1;
      const end = closingTicks(text, index + run, run);
      index = end === -1 ? index + run - 1 : end + run - 1;
    } else if (char === "[") {
      depth += 1;
    } else if (char === "]") {
      depth -= 1;
      if (depth === 0) {
        close = index;
        break;
      }
    }
  }
  if (close === -1 || text[close + 1] !== "(") return null;

  let index = close + 2;
  while (text[index] === " " || text[index] === "\n") index += 1;
  let href = "";
  if (text[index] === "<") {
    const end = text.indexOf(">", index);
    if (end === -1 || text.slice(index + 1, end).includes("\n")) return null;
    href = text.slice(index + 1, end);
    index = end + 1;
  } else {
    let parens = 0;
    while (index < text.length) {
      const char = text[index];
      if (char === "\\" && PUNCTUATION.test(text[index + 1] ?? "")) {
        href += text[index + 1];
        index += 2;
        continue;
      }
      if (/\s/.test(char)) break;
      if (char === "(") parens += 1;
      if (char === ")") {
        if (parens === 0) break;
        parens -= 1;
      }
      href += char;
      index += 1;
    }
  }
  while (text[index] === " " || text[index] === "\n") index += 1;
  let title = null;
  const quote = { '"': '"', "'": "'", "(": ")" }[text[index]];
  if (quote) {
    const end = text.indexOf(quote, index + 1);
    if (end === -1) return null;
    title = text.slice(index + 1, end);
    index = end + 1;
    while (text[index] === " " || text[index] === "\n") index += 1;
  }
  if (text[index] !== ")") return null;
  return { label: text.slice(start + 1, close), href, title, end: index + 1 };
}

// Where emphasis opened at `from` with `marker` closes, or -1.
function closingEmphasis(text, from, marker) {
  const char = marker[0];
  for (let index = from; index < text.length; index += 1) {
    if (text[index] === "\\") {
      index += 1;
      continue;
    }
    if (text[index] === "`") {
      let run = 0;
      while (text[index + run] === "`") run += 1;
      const end = closingTicks(text, index + run, run);
      if (end !== -1) index = end + run - 1;
      continue;
    }
    if (!text.startsWith(marker, index) || /\s/.test(text[index - 1] ?? " ")) continue;
    const after = text[index + marker.length] ?? "";
    if (marker.length === 1 && (text[index - 1] === char || after === char)) continue;
    if (char === "_" && /[\p{L}\p{N}]/u.test(after)) continue;
    if (index === from) continue;
    return index;
  }
  return -1;
}

function renderLink(label, href, title, context) {
  if (!isSafeUrl(href)) return null;
  const rewritten = context.rewriteLink(href);
  if (!isSafeUrl(rewritten)) return null;
  const titleAttribute = title === null ? "" : ` title="${escapeHtml(title)}"`;
  return `<a href="${escapeHtml(rewritten)}"${titleAttribute}>${renderInline(label, context)}</a>`;
}

// Every image needs alt text, so an image without it stops the build.
// Images from other sites would be a third-party request, so they become
// links; an unsafe address leaves only the alt text.
function renderImage(image, context) {
  const alt = htmlToText(renderInline(image.label, context)).replace(/\s+/g, " ").trim();
  if (alt === "") {
    if (context.requireAlt) throw new Error(`an image has no alt text: ${image.href || "(no address)"}.`);
    const href = isSafeUrl(image.href) ? context.rewriteImage(image.href) : "";
    return isSafeUrl(href) ? `<a href="${escapeHtml(href)}">${escapeHtml(href)}</a>` : "";
  }
  if (!isSafeUrl(image.href)) return escapeHtml(alt);
  const src = context.rewriteImage(image.href);
  if (!isSafeUrl(src)) return escapeHtml(alt);
  if (!isSameSite(src)) {
    return `<a href="${escapeHtml(src)}">${escapeHtml(alt)}</a>`;
  }
  const size = context.imageSize(src);
  const dimensions =
    size && Number.isInteger(size.width) && Number.isInteger(size.height) && size.width > 0 && size.height > 0
      ? ` width="${size.width}" height="${size.height}"`
      : "";
  const title = image.title === null ? "" : ` title="${escapeHtml(image.title)}"`;
  return `<img src="${escapeHtml(src)}" alt="${escapeHtml(alt)}"${dimensions}${title} loading="lazy" decoding="async">`;
}

// A paragraph that is nothing but one image.
function loneImage(text) {
  if (!text.startsWith("![")) return null;
  const image = parseLink(text, 1);
  return image && image.end === text.length ? image : null;
}

function renderInline(text, context) {
  let out = "";
  let index = 0;
  while (index < text.length) {
    const char = text[index];

    if (char === "\\" && PUNCTUATION.test(text[index + 1] ?? "")) {
      out += escapeHtml(text[index + 1]);
      index += 2;
      continue;
    }

    if (char === "`") {
      let run = 0;
      while (text[index + run] === "`") run += 1;
      const end = closingTicks(text, index + run, run);
      if (end === -1) {
        out += "`".repeat(run);
        index += run;
        continue;
      }
      let code = text.slice(index + run, end).replaceAll("\n", " ");
      if (/^ .*[^ ].* $/.test(code)) code = code.slice(1, -1);
      out += `<code>${escapeHtml(code)}</code>`;
      index = end + run;
      continue;
    }

    if (char === "<") {
      const auto = /^<([a-zA-Z][a-zA-Z0-9+.-]{1,31}:[^\s<>]*)>/.exec(text.slice(index));
      if (auto && isSafeUrl(auto[1])) {
        out += `<a href="${escapeHtml(context.rewriteLink(auto[1]))}">${escapeHtml(auto[1])}</a>`;
        index += auto[0].length;
        continue;
      }
      out += "&lt;";
      index += 1;
      continue;
    }

    if (char === "!" && text[index + 1] === "[") {
      const image = parseLink(text, index + 1);
      if (image) {
        out += renderImage(image, context);
        index = image.end;
        continue;
      }
    }

    if (char === "[") {
      const link = parseLink(text, index);
      if (link) {
        const html = renderLink(link.label, link.href, link.title, context);
        // An unsafe address keeps only the link's text.
        out += html ?? renderInline(link.label, context);
        index = link.end;
        continue;
      }
    }

    if (char === "*" || char === "_") {
      const before = text[index - 1] ?? " ";
      const canOpen = char === "*" || !/[\p{L}\p{N}]/u.test(before);
      const double = text[index + 1] === char;
      if (canOpen && double && !/\s/.test(text[index + 2] ?? " ")) {
        const end = closingEmphasis(text, index + 2, char + char);
        if (end !== -1) {
          out += `<strong>${renderInline(text.slice(index + 2, end), context)}</strong>`;
          index = end + 2;
          continue;
        }
      }
      if (canOpen && !double && !/\s/.test(text[index + 1] ?? " ")) {
        const end = closingEmphasis(text, index + 1, char);
        if (end !== -1) {
          out += `<em>${renderInline(text.slice(index + 1, end), context)}</em>`;
          index = end + 1;
          continue;
        }
      }
      let run = 0;
      while (text[index + run] === char) run += 1;
      out += char.repeat(run);
      index += run;
      continue;
    }

    out += escapeHtml(char);
    index += 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Rendering

function uniqueId(base, context) {
  const slug = base === "" ? "section" : base;
  const count = context.ids.get(slug);
  context.ids.set(slug, (count ?? -1) + 1);
  return count === undefined ? slug : `${slug}-${count + 1}`;
}

function renderBlocks(blocks, context, tight = false) {
  const parts = [];
  for (const block of blocks) {
    switch (block.type) {
      case "paragraph": {
        const image = loneImage(block.text);
        const html = image ? renderImage(image, context) : renderInline(block.text, context);
        if (image && html.startsWith("<img ")) {
          parts.push(`<figure class="doc-image">${html}</figure>`);
        } else {
          parts.push(tight ? html : `<p>${html}</p>`);
        }
        break;
      }
      case "heading": {
        const html = renderInline(block.text, context);
        const text = htmlToText(html).trim();
        const level = Math.min(6, Math.max(1, block.level + context.shift));
        const id = context.idPrefix + uniqueId(slugify(text), context);
        context.headings.push({ level, sourceLevel: block.level, text, id });
        parts.push(`<h${level} id="${escapeHtml(id)}">${html}</h${level}>`);
        break;
      }
      case "code": {
        const language = block.language ? ` class="language-${escapeHtml(block.language)}"` : "";
        parts.push(`<pre><code${language}>${escapeHtml(block.text)}</code></pre>`);
        break;
      }
      case "rule":
        parts.push("<hr>");
        break;
      case "quote":
        parts.push(`<blockquote>\n${renderBlocks(block.children, context)}\n</blockquote>`);
        break;
      case "list": {
        const tag = block.ordered ? "ol" : "ul";
        const start = block.ordered && block.start !== 1 ? ` start="${block.start}"` : "";
        const items = block.items.map((item) => `<li>${renderBlocks(item, context, !block.loose)}</li>`);
        parts.push(`<${tag}${start}>\n${items.join("\n")}\n</${tag}>`);
        break;
      }
      case "table": {
        const cell = (tag, text, column) => {
          const align = block.align[column] ? ` class="align-${block.align[column]}"` : "";
          return `<${tag}${align}>${renderInline(text ?? "", context)}</${tag}>`;
        };
        const head = block.header.map((text, column) => cell("th", text, column)).join("");
        const rows = block.rows.map(
          (row) => `<tr>${block.header.map((_, column) => cell("td", row[column], column)).join("")}</tr>`,
        );
        parts.push(
          `<div class="table-wrap">\n<table>\n<thead>\n<tr>${head}</tr>\n</thead>\n` +
            (rows.length > 0 ? `<tbody>\n${rows.join("\n")}\n</tbody>\n` : "") +
            "</table>\n</div>",
        );
        break;
      }
      default:
        throw new Error(`Unknown Markdown block: ${block.type}`);
    }
  }
  return parts.join("\n");
}

function lowestHeading(blocks) {
  let lowest = Infinity;
  for (const block of blocks) {
    if (block.type === "heading") lowest = Math.min(lowest, block.level);
    if (block.type === "quote") lowest = Math.min(lowest, lowestHeading(block.children));
    if (block.type === "list") for (const item of block.items) lowest = Math.min(lowest, lowestHeading(item));
  }
  return lowest;
}

// Renders Markdown and returns the HTML, every heading with its id, and the
// plain text of the first paragraph.
//
// Options:
// - rewriteLink(href): returns the address to use for a link.
// - rewriteImage(src): returns the address to use for an image (default: rewriteLink).
// - imageSize(src): returns { width, height } for an image on this site, or null.
// - topHeadingLevel: shifts the headings so the biggest becomes this level.
// - idPrefix: put before every heading's id.
// - requireAlt: an image without alt text throws (the default), or becomes a link.
function contextFrom(
  { rewriteLink = (href) => href, rewriteImage = rewriteLink, imageSize = () => null, idPrefix = "", requireAlt = true } = {},
  shift = 0,
) {
  return { rewriteLink, rewriteImage, imageSize, requireAlt, shift, idPrefix, ids: new Map(), headings: [] };
}

export function renderMarkdownDocument(source, options = {}) {
  const lines = String(source).replace(/\r\n?/g, "\n").split("\n").map(expandTabs);
  const blocks = parseBlocks(lines);
  const lowest = lowestHeading(blocks);
  const top = options.topHeadingLevel ?? null;
  const shift = top !== null && lowest !== Infinity ? top - lowest : 0;
  const context = contextFrom(options, shift);
  const html = renderBlocks(blocks, context);
  const first = blocks.find((block) => block.type === "paragraph" && !loneImage(block.text));
  const firstParagraph = first ? htmlToText(renderInline(first.text, contextFrom(options))).replace(/\s+/g, " ").trim() : "";
  return { html, headings: context.headings, firstParagraph };
}

export function renderMarkdown(source, options) {
  return renderMarkdownDocument(source, options).html;
}

// One line of Markdown, such as a blurb, without a surrounding paragraph.
export function renderMarkdownInline(text, options) {
  return renderInline(String(text), contextFrom(options));
}

// The pixel size of a PNG or WebP image from its header, or null.
export function imageDimensions(bytes) {
  const data = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes ?? []);
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const ascii = (start, length) => String.fromCharCode(...data.subarray(start, start + length));
  if (data.length >= 24 && ascii(1, 3) === "PNG" && ascii(12, 4) === "IHDR") {
    return { width: view.getUint32(16), height: view.getUint32(20) };
  }
  if (data.length >= 30 && ascii(0, 4) === "RIFF" && ascii(8, 4) === "WEBP") {
    const chunk = ascii(12, 4);
    if (chunk === "VP8 " && data[23] === 0x9d && data[24] === 0x01 && data[25] === 0x2a) {
      return { width: view.getUint16(26, true) & 0x3fff, height: view.getUint16(28, true) & 0x3fff };
    }
    if (chunk === "VP8L" && data[20] === 0x2f) {
      const bits = view.getUint32(21, true);
      return { width: (bits & 0x3fff) + 1, height: ((bits >> 14) & 0x3fff) + 1 };
    }
    if (chunk === "VP8X") {
      const width = 1 + (data[24] | (data[25] << 8) | (data[26] << 16));
      const height = 1 + (data[27] | (data[28] << 8) | (data[29] << 16));
      return { width, height };
    }
  }
  return null;
}
