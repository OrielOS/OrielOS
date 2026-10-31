// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import { mkdir, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

import {
  buildWiki,
  pageNameFrom,
  parseArguments,
  removeHeading,
  renderFooter,
  rewriteLinks,
  wikiLinkMapper,
} from "../build-wiki.mjs";

const repo = "example/Repo";
const base = `https://github.com/${repo}`;
const script = fileURLToPath(new URL("../build-wiki.mjs", import.meta.url));
const repoRoot = fileURLToPath(new URL("../..", import.meta.url));

function convert(markdown, files = ["a.md", "my-page.md"]) {
  const pages = new Map(files.map((file) => [file, file === "a.md" ? "Page-A" : "My-Page"]));
  return rewriteLinks(markdown, wikiLinkMapper({ pages, repo, docsPath: "docs", sourceFile: "docs/a.md" }));
}

test("names pages after their first heading", () => {
  assert.equal(pageNameFrom("# Try OrielOS in a virtual machine\n", "x.md"), "Try-OrielOS-in-a-virtual-machine");
  assert.equal(pageNameFrom("# Games: with   anti-cheat!\n", "x.md"), "Games-with-anticheat");
  assert.equal(pageNameFrom("Intro\n\n```\n# not a title\n```\n", "notes.md"), "notes");
  assert.equal(pageNameFrom("# README title\n", "README.md"), "Home");
});

test("removes the first heading and one blank line", () => {
  assert.equal(removeHeading("# Title\n\nText\n\nMore\n"), "Text\n\nMore\n");
  assert.equal(removeHeading("# Title\nText\n"), "Text\n");
  assert.equal(removeHeading("Text\n"), "Text\n");
  assert.equal(removeHeading("```\n# code\n```\n# Real\n\nBody\n"), "```\n# code\n```\nBody\n");
});

test("maps links to docs pages, keeping anchors", () => {
  assert.equal(convert("[a](a.md) [b](./my-page.md#part)"), "[a](Page-A) [b](My-Page#part)");
  });

test("maps README.md to Home", () => {
  const pages = new Map([["README.md", "Home"]]);
  const map = wikiLinkMapper({ pages, repo, docsPath: "docs", sourceFile: "docs/a.md" });
  assert.equal(map("README.md#top", false), "Home#top");
});

test("maps other relative paths to GitHub", () => {
  assert.equal(convert("[l](LICENSE)"), `[l](${base}/blob/main/docs/LICENSE)`);
  assert.equal(convert("[t](../tools/lint.sh#L3)"), `[t](${base}/blob/main/tools/lint.sh#L3)`);
  assert.equal(convert("[c](../CONTRIBUTING.md)"), `[c](${base}/blob/main/CONTRIBUTING.md)`);
  assert.equal(convert("[d](../tools/)"), `[d](${base}/tree/main/tools)`);
});

test("maps images to raw files", () => {
  assert.equal(convert("![alt](shot.png)"), `![alt](${base}/raw/main/docs/shot.png)`);
  assert.equal(convert('![alt](../artwork/a.svg "Title")'), `![alt](${base}/raw/main/artwork/a.svg "Title")`);
});

test("maps reference definitions", () => {
  assert.equal(convert("[id]: a.md\n[two]: ../x.md"), `[id]: Page-A\n[two]: ${base}/blob/main/x.md`);
});

test("leaves absolute and fragment-only links alone", () => {
  const text = "[a](https://example.org/a.md) [b](http://x.org) [c](mailto:me@example.org) [d](#section)";
  assert.equal(convert(text), text);
});

test("leaves code untouched", () => {
  const text = "```md\n[a](a.md)\n```\n~~~\n[a](a.md)\n~~~\nUse `[a](a.md)` or ``[a](a.md)``.";
  assert.equal(convert(text), text);
  assert.equal(convert("`x` [a](a.md)"), "`x` [a](Page-A)");
});

test("fails on a link to a missing docs page", () => {
  assert.throws(() => convert("[x](missing.md)"), /docs\/a\.md links to missing\.md/);
});

test("orders the sidebar by the README, then by name", () => {
  const output = buildWiki(
    [
      { file: "README.md", content: "# docs\n\n- [Z](zebra.md)\n- [M](mango.md)\n" },
      { file: "apple.md", content: "# Apple\n" },
      { file: "mango.md", content: "# Mango\n" },
      { file: "zebra.md", content: "# Zebra\n" },
      { file: "banana.md", content: "# Banana\n" },
    ],
    { repo },
  );
  assert.equal(
    output.get("_Sidebar.md"),
    "### Documentation\n\n- [Home](Home)\n- [Zebra](Zebra)\n- [Mango](Mango)\n- [Apple](Apple)\n- [Banana](Banana)\n",
  );
  assert.equal(output.get("Home.md"), "- [Z](Zebra)\n- [M](Mango)\n");
});

test("the sidebar shows each page's heading, punctuation included", () => {
  const output = buildWiki([{ file: "anti-cheat.md", content: "# Games with anti-cheat\n" }], { repo });
  assert.ok(output.has("Games-with-anticheat.md"));
  assert.match(output.get("_Sidebar.md"), /- \[Games with anti-cheat\]\(Games-with-anticheat\)\n/);
});

test("the footer names the repository", () => {
  const footer = renderFooter(repo);
  assert.ok(footer.includes(`[\`docs/\`](${base}/tree/main/docs)`));
  assert.match(footer, /edits made here are lost/);
  assert.ok(footer.endsWith(`[CC BY-SA 4.0](${base}/blob/main/docs/LICENSE).\n`));
});

test("fails when two files map to one page name", () => {
  assert.throws(
    () =>
      buildWiki(
        [
          { file: "a.md", content: "# Same name\n" },
          { file: "b.md", content: "# Same name!\n" },
        ],
        { repo },
      ),
    /docs\/b\.md and docs\/a\.md would both become the wiki page "Same-name"/,
  );
});

test("parses arguments and defaults", () => {
  assert.deepEqual(parseArguments(["--out", "o"], { GITHUB_REPOSITORY: "a/b" }), { out: "o", repo: "a/b", docs: "docs" });
  assert.equal(parseArguments(["--out", "o"], {}).repo, "OrielOS/OrielOS");
  assert.throws(() => parseArguments([], {}), /Missing --out/);
});

function run(...args) {
  return spawnSync(process.execPath, [script, ...args], { encoding: "utf8" });
}

test("fails when the output directory is not empty", async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), "wiki-test-"));
  try {
    await writeFile(path.join(dir, "old.md"), "old");
    const result = run("--out", dir);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /not empty/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("fails on a link to a docs page that does not exist", async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), "wiki-test-"));
  try {
    const docs = path.join(dir, "docs");
    await mkdir(docs);
    await writeFile(path.join(docs, "README.md"), "# docs\n\n[x](nope.md)\n");
    const result = run("--docs", docs, "--out", path.join(dir, "out"));
    assert.equal(result.status, 1);
    assert.match(result.stderr, /README\.md links to nope\.md/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("builds the real docs into a new directory", async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), "wiki-test-"));
  const out = path.join(dir, "wiki");
  try {
    const result = run("--out", out, "--repo", repo);
    assert.equal(result.status, 0, result.stderr);
    const sources = (await readdir(path.join(repoRoot, "docs"))).filter((file) => file.endsWith(".md"));
    const built = (await readdir(out)).sort();
    assert.equal(built.length, sources.length + 2);
    for (const name of ["Home.md", "_Sidebar.md", "_Footer.md"]) assert.ok(built.includes(name), name);
    for (const name of built) {
      const text = await readFile(path.join(out, name), "utf8");
      assert.doesNotMatch(text, /\r/);
      for (const source of sources) {
        assert.ok(!text.includes(`](${source}`), `${name} still links to ${source}`);
      }
      assert.doesNotMatch(text, /\]\((?:\.\/)?[\w-]+\.md[#)]/, name);
    }
    assert.doesNotMatch(await readFile(path.join(out, "Home.md"), "utf8"), /^# /m);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
