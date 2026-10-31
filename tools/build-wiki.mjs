// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Builds the GitHub wiki from the user documentation in docs/.
//
// Usage: node tools/build-wiki.mjs --out <dir> [--repo <owner/name>] [--docs <dir>]
//
// Turns every top-level docs/*.md file into a wiki page (docs/README.md becomes
// Home), rewrites relative links so they work on the wiki and on GitHub, and
// writes a sidebar and a footer. --repo defaults to $GITHUB_REPOSITORY, else
// OrielOS/OrielOS. --docs defaults to docs. --out is created if missing and must
// be empty. docs/ stays the only source: the wiki is a generated copy.

import { mkdir, readdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..");

const DEFAULT_REPO = "OrielOS/OrielOS";
const HOME = "Home";

// Page naming

export function pageNameFrom(markdown, fileName) {
  if (fileName === "README.md") return HOME;
  const title = firstHeading(markdown)?.title ?? "";
  const name = title
    .replace(/[^\p{L}\p{N} ]/gu, "")
    .trim()
    .replace(/ +/g, "-");
  return name === "" ? fileName.replace(/\.md$/, "") : name;
}

// The first "# " line outside a fenced code block, with its line index.
export function firstHeading(markdown) {
  const lines = markdown.split("\n");
  let fence = null;
  for (let index = 0; index < lines.length; index += 1) {
    fence = nextFenceState(fence, lines[index]);
    if (fence === null && /^# /.test(lines[index])) {
      return { index, title: lines[index].slice(2).trim() };
    }
  }
  return null;
}

// Removes the first H1 and one blank line after it: the wiki shows the page
// name as the title.
export function removeHeading(markdown) {
  const heading = firstHeading(markdown);
  if (heading === null) return markdown;
  const lines = markdown.split("\n");
  const count = lines[heading.index + 1] === "" ? 2 : 1;
  lines.splice(heading.index, count);
  return lines.join("\n");
}

// Links

// Tracks fenced code blocks. Returns the open fence ({ char, length }) once this
// line has been read, or null when no fence is open. A line is code if a fence
// was open before it or is open after it.
function nextFenceState(fence, line) {
  const match = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line);
  if (match === null) return fence;
  const [, marker, rest] = match;
  if (fence === null) {
    if (marker[0] === "`" && rest.includes("`")) return fence;
    return { char: marker[0], length: marker.length };
  }
  if (marker[0] === fence.char && marker.length >= fence.length && rest.trim() === "") {
    return null;
  }
  return fence;
}

const CODE_SPAN = /(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)/g;
const INLINE_LINK = /(!?)\[((?:[^\]\\]|\\.)*)\]\(\s*(<[^>]*>|[^)\s]*)((?:\s+(?:"[^"]*"|'[^']*'))?\s*)\)/g;
const REFERENCE_DEFINITION = /^( {0,3}\[[^\]]+\]:\s*)(<[^>]*>|\S+)/;

// Calls mapTarget(target, isImage) for every link target outside code and
// replaces it with the result.
export function rewriteLinks(markdown, mapTarget) {
  let fence = null;
  return markdown
    .split("\n")
    .map((line) => {
      const before = fence;
      fence = nextFenceState(fence, line);
      if (before !== null || fence !== null) return line;
      return rewriteLine(line, mapTarget);
    })
    .join("\n");
}

function rewriteLine(line, mapTarget) {
  const spans = [];
  const masked = line.replace(CODE_SPAN, (span) => {
    spans.push(span);
    return `\u0000${spans.length - 1}\u0000`;
  });
  const rewritten = masked
    .replace(INLINE_LINK, (all, bang, text, target, title) => {
      const bare = target.replace(/^<|>$/g, "");
      return `${bang}[${text}](${mapTarget(bare, bang === "!")}${title})`;
    })
    .replace(REFERENCE_DEFINITION, (all, head, target) => {
      return head + mapTarget(target.replace(/^<|>$/g, ""), false);
    });
  return rewritten.replace(/\u0000(\d+)\u0000/g, (all, index) => spans[Number(index)]);
}

// Returns the function that maps one link target to its wiki form. pages maps
// a docs file name to its page name; docsPath is the docs folder relative to
// the repository root, with forward slashes. sourceFile names the file being
// converted, for error messages.
export function wikiLinkMapper({ pages, repo, docsPath, sourceFile }) {
  const base = `https://github.com/${repo}`;
  return (target, isImage) => {
    if (target === "" || target.startsWith("#") || /^[a-z][a-z0-9+.-]*:/i.test(target)) {
      return target;
    }
    const hashAt = target.indexOf("#");
    const file = hashAt === -1 ? target : target.slice(0, hashAt);
    const fragment = hashAt === -1 ? "" : target.slice(hashAt);
    const resolved = path.posix.normalize(path.posix.join(docsPath, file));

    if (path.posix.dirname(resolved) === docsPath && resolved.endsWith(".md")) {
      const name = pages.get(path.posix.basename(resolved));
      if (name === undefined) {
        throw new Error(`${sourceFile} links to ${file}, which is not a page in ${docsPath}/.`);
      }
      return `${name}${fragment}`;
    }
    if (file.endsWith("/")) return `${base}/tree/main/${resolved.replace(/\/$/, "")}${fragment}`;
    return `${base}/${isImage ? "raw" : "blob"}/main/${resolved}${fragment}`;
  };
}

// Pages, sidebar and footer

// Page names in the order docs/README.md links them, then the rest by name.
export function sidebarOrder(readmeMarkdown, pages, mapTarget) {
  const names = new Set(pages.values());
  const linked = [];
  rewriteLinks(readmeMarkdown, (target, isImage) => {
    const mapped = mapTarget(target, isImage);
    const name = mapped.split("#")[0];
    if (names.has(name) && !linked.includes(name)) linked.push(name);
    return mapped;
  });
  const rest = [...names].filter((name) => !linked.includes(name)).sort();
  return [HOME, ...linked.filter((name) => name !== HOME), ...rest.filter((name) => name !== HOME)];
}

// titles maps a page name to the heading it came from, so the sidebar keeps
// punctuation that page names drop.
export function renderSidebar(names, titles = new Map()) {
  const items = names.map((name) => `- [${titles.get(name) ?? name.replaceAll("-", " ")}](${name})`);
  return `### Documentation\n\n${items.join("\n")}\n`;
}

export function renderFooter(repo) {
  return (
    `This wiki is generated from [\`docs/\`](https://github.com/${repo}/tree/main/docs) ` +
    "and is replaced each time the documentation changes, so edits made here are lost. " +
    "To improve a page, open a pull request that changes the file in `docs/`. " +
    `Documentation licence: [CC BY-SA 4.0](https://github.com/${repo}/blob/main/docs/LICENSE).\n`
  );
}

// sources: [{ file: "apps.md", content: "..." }]. Returns Map(file name -> text)
// of wiki files, including _Sidebar.md and _Footer.md.
export function buildWiki(sources, { repo, docsPath = "docs" }) {
  const pages = new Map();
  const owners = new Map();
  const titles = new Map();
  for (const { file, content } of sources) {
    const name = pageNameFrom(content, file);
    const clash = owners.get(name.toLowerCase());
    if (clash !== undefined) {
      throw new Error(`${docsPath}/${file} and ${docsPath}/${clash} would both become the wiki page "${name}".`);
    }
    owners.set(name.toLowerCase(), file);
    pages.set(file, name);
    if (name !== HOME) titles.set(name, firstHeading(content)?.title ?? name.replaceAll("-", " "));
  }

  const output = new Map();
  for (const { file, content } of sources) {
    const mapTarget = wikiLinkMapper({ pages, repo, docsPath, sourceFile: `${docsPath}/${file}` });
    output.set(`${pages.get(file)}.md`, rewriteLinks(removeHeading(content), mapTarget));
  }

  const readme = sources.find((source) => source.file === "README.md");
  const names = readme
    ? sidebarOrder(
        readme.content,
        pages,
        wikiLinkMapper({ pages, repo, docsPath, sourceFile: `${docsPath}/README.md` }),
      )
    : [...pages.values()].sort();
  output.set("_Sidebar.md", renderSidebar(names, titles));
  output.set("_Footer.md", renderFooter(repo));
  return output;
}

// Command line

export function parseArguments(argv, env = process.env) {
  const options = { out: "", repo: env.GITHUB_REPOSITORY || DEFAULT_REPO, docs: "docs" };
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!["--out", "--repo", "--docs"].includes(flag) || value === undefined) {
      throw new Error(`Unexpected argument: ${flag}. ${USAGE}`);
    }
    options[flag.slice(2)] = value;
  }
  if (options.out === "") throw new Error(`Missing --out. ${USAGE}`);
  return options;
}

const USAGE = "Usage: node tools/build-wiki.mjs --out <dir> [--repo <owner/name>] [--docs <dir>]";

async function ensureEmptyDirectory(dir) {
  let entries = [];
  try {
    await stat(dir);
    entries = await readdir(dir);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  if (entries.length > 0) {
    throw new Error(`The output directory ${dir} is not empty.`);
  }
  await mkdir(dir, { recursive: true });
}

async function readSources(docsDir) {
  const entries = await readdir(docsDir, { withFileTypes: true });
  const files = entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
    .map((entry) => entry.name)
    .sort();
  return Promise.all(
    files.map(async (file) => ({
      file,
      content: (await readFile(path.join(docsDir, file), "utf8")).replace(/\r\n?/g, "\n"),
    })),
  );
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const docsDir = path.resolve(repoRoot, options.docs);
  const docsPath = path.relative(repoRoot, docsDir).split(path.sep).join("/");
  const outDir = path.resolve(options.out);

  await ensureEmptyDirectory(outDir);
  const output = buildWiki(await readSources(docsDir), { repo: options.repo, docsPath });
  for (const [name, text] of output) {
    await writeFile(path.join(outDir, name), text, "utf8");
  }
  console.log(`Built ${output.size} wiki files in ${outDir}.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`Wiki build failed: ${error.message}`);
    process.exit(1);
  });
}
