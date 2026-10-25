// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import { escapeMarkdown } from "discord.js";

import { crosspost, sendMessage } from "./discord-api.js";

const COLOUR = 0x3a66f0;
const MAX_TITLE = 256;
const MAX_NOTES = 1000;
const MAX_COMMITS = 10;

function isGitHubUrl(value) {
  return typeof value === "string" && value.startsWith("https://github.com/");
}

// Escapes Discord markdown, then cuts to the limit without leaving a lone backslash.
export function clean(text, max) {
  const escaped = escapeMarkdown(String(text ?? ""));
  if (escaped.length <= max) return escaped;
  let cut = escaped.slice(0, max - 1);
  const slashes = cut.length - cut.replace(/\\+$/, "").length;
  if (slashes % 2 === 1) cut = cut.slice(0, -1);
  return `${cut}…`;
}

export function truncate(text, max) {
  return text.length <= max ? text : `${text.slice(0, max - 1)}…`;
}

export function isoFrom(assets) {
  if (!Array.isArray(assets)) return null;
  const asset = assets.find(
    (item) =>
      typeof item?.name === "string" &&
      item.name.toLowerCase().endsWith(".iso") &&
      (item.state === undefined || item.state === "uploaded") &&
      isGitHubUrl(item.browser_download_url) &&
      Number.isInteger(item.size),
  );
  if (!asset) return null;
  const digest = typeof asset.digest === "string" ? asset.digest : "";
  const sha256 = /^sha256:[0-9a-f]{64}$/.test(digest) ? digest.slice("sha256:".length) : "";
  return { url: asset.browser_download_url, size: formatSize(asset.size), sha256 };
}

export function formatSize(bytes) {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`;
  return `${Math.max(1, Math.round(bytes / 1e6))} MB`;
}

function releaseMessages(payload) {
  const release = payload.release;
  if (payload.action !== "published" || !release || release.draft) return [];
  const name = [release.name, release.tag_name].find(
    (value) => typeof value === "string" && value !== "",
  );
  if (name === undefined) return [];
  const embed = {
    title: clean(
      release.prerelease ? `Pre-release: ${name}` : `OrielOS ${name} is out`,
      MAX_TITLE,
    ),
    color: COLOUR,
  };
  if (isGitHubUrl(release.html_url)) embed.url = release.html_url;
  // Release notes are written by maintainers in Markdown, so they keep their formatting.
  if (typeof release.body === "string" && release.body.trim() !== "") {
    embed.description = truncate(release.body.trim(), MAX_NOTES);
  }
  const iso = isoFrom(release.assets);
  if (iso) {
    embed.fields = [{ name: "Installer", value: `[Download the ISO](${iso.url}) (${iso.size})` }];
  }
  return [{ embeds: [embed] }];
}

function isBotCommit(commit) {
  return (
    String(commit?.author?.name ?? "").endsWith("[bot]") ||
    String(commit?.author?.username ?? "").endsWith("[bot]")
  );
}

function commitEmbed(commit, repo) {
  const title = String(commit.message ?? "").split("\n")[0];
  const pull = /\s\(#(\d+)\)$/.exec(title);
  const embed = { title: clean(`Merged: ${title}`, MAX_TITLE), color: COLOUR };
  if (pull) embed.url = `https://github.com/${repo}/pull/${pull[1]}`;
  else if (isGitHubUrl(commit.url)) embed.url = commit.url;
  if (commit.author?.username) embed.footer = { text: commit.author.username };
  if (commit.timestamp) embed.timestamp = commit.timestamp;
  return embed;
}

function pushMessages(payload, repo) {
  if (payload.ref !== "refs/heads/main" || !Array.isArray(payload.commits)) return [];
  const commits = payload.commits.filter((commit) => !isBotCommit(commit));
  const embeds = commits.slice(0, MAX_COMMITS).map((commit) => commitEmbed(commit, repo));
  if (commits.length > MAX_COMMITS) {
    embeds[MAX_COMMITS - 1] = {
      title: `and ${commits.length - (MAX_COMMITS - 1)} more changes`,
      color: COLOUR,
    };
  }
  return embeds.map((embed) => ({ embeds: [embed] }));
}

export function messagesFor(eventName, payload, repo) {
  if (eventName === "release") return releaseMessages(payload ?? {});
  if (eventName === "push") return pushMessages(payload ?? {}, repo);
  return [];
}

export async function sendPosts(rest, feed, messages) {
  for (const body of messages) {
    const sent = await sendMessage(rest, feed.id, body);
    if (feed.type === 5) {
      try {
        await crosspost(rest, feed.id, sent.id);
      } catch {
        // Crossposting is a bonus; the message is already in the channel.
      }
    }
  }
}
