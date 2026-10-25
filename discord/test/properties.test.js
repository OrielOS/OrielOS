// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import assert from "node:assert/strict";
import test from "node:test";

import { escapeMarkdown } from "discord.js";
import fc from "fast-check";

import { maintainersFromCodeowners, nextLink } from "../src/github.js";
import { clean, formatSize, isoFrom, truncate } from "../src/posts.js";
import { parseRecord, serialiseRecord } from "../src/store.js";

// Well-formed text that leans on markdown characters and emoji, as GitHub titles can.
const text = fc.string({
  unit: fc.oneof(
    fc.constantFrom("\\", "*", "_", "`", "~", "|", ">", "#", "-", "@", " ", "😀", "👨‍👩‍👧"),
    fc.string({ unit: "binary", minLength: 1, maxLength: 1 }),
  ),
  maxLength: 400,
});
const limit = fc.integer({ min: 2, max: 300 });

function trailingBackslashes(value) {
  return value.length - value.replace(/\\+$/, "").length;
}

test("clean stays within the limit and never cuts an emoji in half", () => {
  fc.assert(
    fc.property(text, limit, (value, max) => {
      const result = clean(value, max);
      const escaped = escapeMarkdown(value);
      assert.ok(result.length <= max);
      assert.ok(result.isWellFormed());
      if (escaped.length <= max) {
        assert.equal(result, escaped);
      } else {
        assert.ok(result.endsWith("…"));
        assert.equal(trailingBackslashes(result.slice(0, -1)) % 2, 0);
      }
    }),
  );
  assert.equal(clean(null, 10), "");
  assert.equal(clean(undefined, 10), "");
});

test("truncate stays within the limit and never cuts an emoji in half", () => {
  fc.assert(
    fc.property(text, limit, (value, max) => {
      const result = truncate(value, max);
      assert.ok(result.length <= max);
      assert.ok(result.isWellFormed());
      if (value.length <= max) assert.equal(result, value);
      else assert.ok(result.endsWith("…"));
    }),
  );
});

test("parseRecord never throws and only returns known kinds", () => {
  const kinds = new Set(["link", "welcome", "feed", "optin"]);
  fc.assert(
    fc.property(fc.oneof(fc.string(), fc.json()), (content) => {
      const record = parseRecord(content);
      assert.ok(record === null || kinds.has(record.kind));
    }),
  );
});

test("every valid record survives a round trip through its message", () => {
  const plain = { noNullPrototype: true };
  const record = fc.oneof(
    fc.record(
      {
        kind: fc.constant("link"),
        discord: fc.string(),
        github: fc.integer(),
        login: fc.string(),
        at: fc.string(),
        on: fc.string(),
      },
      { ...plain, requiredKeys: ["kind", "discord", "github", "login", "at"] },
    ),
    fc.record({ kind: fc.constant("welcome"), message: fc.string() }, plain),
    fc.record(
      { kind: fc.constant("feed"), pr: fc.nat(), stars: fc.nat() },
      { ...plain, requiredKeys: ["kind", "pr"] },
    ),
    fc.record(
      {
        kind: fc.constant("optin"),
        role: fc.stringMatching(/^[a-z]+$/),
        discord: fc.string({ minLength: 1 }),
      },
      plain,
    ),
  );
  fc.assert(
    fc.property(record, (value) => {
      assert.deepEqual(parseRecord(serialiseRecord(value)), value);
    }),
  );
});

test("nextLink never throws and finds the first next page", () => {
  fc.assert(
    fc.property(fc.string(), (header) => {
      const url = nextLink(header);
      assert.ok(url === null || typeof url === "string");
    }),
  );
  const entry = fc.record({
    url: fc.webUrl().filter((url) => !/[<>,]/.test(url)),
    rel: fc.constantFrom("next", "prev", "first", "last"),
  });
  fc.assert(
    fc.property(fc.array(entry, { maxLength: 5 }), (entries) => {
      const header = entries.map(({ url, rel }) => `<${url}>; rel="${rel}"`).join(", ");
      const next = entries.find(({ rel }) => rel === "next");
      assert.equal(nextLink(header), next ? next.url : null);
    }),
  );
  assert.equal(nextLink(undefined), null);
  assert.equal(nextLink(""), null);
});

test("maintainersFromCodeowners only returns valid GitHub usernames", () => {
  const line = fc.oneof(
    fc.string(),
    fc.constantFrom(
      "* @Some-User @other",
      "# comment",
      "docs/ @x",
      "* @bad_name",
      "*  @a # @b",
      "* @-dash @end-",
      "",
    ),
  );
  const file = fc
    .tuple(fc.array(line, { maxLength: 8 }), fc.constantFrom("\n", "\r\n"))
    .map(([lines, end]) => lines.join(end));
  fc.assert(
    fc.property(fc.oneof(fc.string(), file), (content) => {
      for (const owner of maintainersFromCodeowners(content)) {
        assert.match(owner, /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/);
      }
    }),
  );
});

test("isoFrom never throws and only links to GitHub downloads", () => {
  const hex = fc.string({ unit: fc.constantFrom(..."0123456789abcdef"), minLength: 64, maxLength: 64 });
  const asset = fc.record(
    {
      name: fc.oneof(fc.constantFrom("OrielOS.iso", "notes.txt", "X.ISO"), fc.anything()),
      state: fc.oneof(fc.constantFrom("uploaded", "starter"), fc.anything()),
      size: fc.oneof(fc.nat(), fc.anything()),
      browser_download_url: fc.oneof(
        fc.constantFrom("https://github.com/x.iso", "http://github.com/x.iso", "https://example.com/x.iso"),
        fc.anything(),
      ),
      digest: fc.oneof(hex.map((value) => `sha256:${value}`), fc.anything()),
    },
    { requiredKeys: [] },
  );
  fc.assert(
    fc.property(fc.oneof(fc.anything(), fc.array(asset, { maxLength: 4 })), (assets) => {
      const iso = isoFrom(assets);
      if (iso === null) return;
      assert.ok(iso.url.startsWith("https://github.com/"));
      assert.match(iso.sha256, /^(|[0-9a-f]{64})$/);
    }),
  );
});

test("formatSize always gives whole megabytes or tenths of a gigabyte", () => {
  fc.assert(
    fc.property(fc.integer({ min: 0, max: 1e13 }), (bytes) => {
      assert.match(formatSize(bytes), /^(\d+ MB|\d+\.\d GB)$/);
    }),
  );
});
