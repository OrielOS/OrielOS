// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import { escapeMarkdown } from "discord.js";

import { crosspost, sendMessage } from "./discord-api.js";

const COLOUR = 0x3a66f0;
const MAX_TITLE = 256;
const MAX_NOTES = 1000;
const MAX_FIELD = 1024;
const MAX_COMMITS = 10;
const MIN_LABEL_DELAY_MS = 120000;
const FIRST_ISSUE_LABEL = "good first issue";
export const STAR_MILESTONES = [
  10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000,
];

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
      release.prerelease ? `Test build ${name} is ready` : `OrielOS ${name} is out`,
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
  // Full releases ping everyone; test builds ping the Testers role (post.js adds it); merges never ping.
  if (release.prerelease) return [{ embeds: [embed], crosspost: true, pingTesters: true }];
  return [
    { content: "@everyone", embeds: [embed], mentions: { parse: ["everyone"] }, crosspost: true },
  ];
}

function isBotCommit(commit) {
  return (
    String(commit?.author?.name ?? "").endsWith("[bot]") ||
    String(commit?.author?.username ?? "").endsWith("[bot]")
  );
}

function commitUrl(commit, title, repo) {
  const pull = /\s\(#(\d+)\)$/.exec(title);
  if (pull) return `https://github.com/${repo}/pull/${pull[1]}`;
  return isGitHubUrl(commit.url) ? commit.url : null;
}

function commitEmbed(commit, repo) {
  const title = String(commit.message ?? "").split("\n")[0];
  const embed = { title: clean(`Merged: ${title}`, MAX_TITLE), color: COLOUR };
  const url = commitUrl(commit, title, repo);
  if (url) embed.url = url;
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

// Non-bot commits to main with a GitHub username, one per username.
export function firstContributionCandidates(payload) {
  if (payload?.ref !== "refs/heads/main" || !Array.isArray(payload.commits)) return [];
  const seen = new Set();
  const candidates = [];
  for (const commit of payload.commits) {
    const username = commit?.author?.username;
    if (typeof username !== "string" || username === "" || isBotCommit(commit)) continue;
    if (seen.has(username.toLowerCase())) continue;
    seen.add(username.toLowerCase());
    candidates.push({ username, commit });
  }
  return candidates;
}

export function welcomeMessage({ username, commit }, repo) {
  const title = String(commit.message ?? "").split("\n")[0];
  const embed = {
    title: clean(`Welcome, ${username}: first contribution merged`, MAX_TITLE),
    description: clean(title, MAX_TITLE),
    color: COLOUR,
    author: {
      name: clean(username, MAX_TITLE),
      url: `https://github.com/${encodeURIComponent(username)}`,
    },
  };
  const url = commitUrl(commit, title, repo);
  if (url) embed.url = url;
  if (commit.timestamp) embed.timestamp = commit.timestamp;
  return { embeds: [embed] };
}

function isBotUser(user) {
  return user?.type === "Bot" || String(user?.login ?? "").endsWith("[bot]");
}

function authorOf(user) {
  const author = { name: clean(user?.login, MAX_TITLE) };
  if (isGitHubUrl(user?.html_url)) author.url = user.html_url;
  return author;
}

function itemEmbed(title, item) {
  const embed = { title: clean(title, MAX_TITLE), color: COLOUR, author: authorOf(item.user) };
  if (isGitHubUrl(item.html_url)) embed.url = item.html_url;
  if (typeof item.created_at === "string") embed.timestamp = item.created_at;
  return embed;
}

const isFirstIssueLabel = (name) => String(name ?? "").toLowerCase() === FIRST_ISSUE_LABEL;

function labeledIssueMessages(payload) {
  const issue = payload.issue;
  if (!issue || issue.state !== "open" || isBotUser(issue.user)) return [];
  if (!isFirstIssueLabel(payload.label?.name)) return [];
  // Labels given at creation already show in the opened post.
  const delay = Date.parse(issue.updated_at) - Date.parse(issue.created_at);
  if (!(delay >= MIN_LABEL_DELAY_MS)) return [];
  const embed = itemEmbed(`Good first issue #${issue.number}: ${issue.title ?? ""}`, issue);
  embed.timestamp = issue.updated_at;
  return [{ embeds: [embed] }];
}

function issueMessages(payload) {
  const issue = payload.issue;
  if (payload.action === "labeled") return labeledIssueMessages(payload);
  if (payload.action !== "opened" || !issue || isBotUser(issue.user)) return [];
  const all = Array.isArray(issue.labels) ? issue.labels : [];
  const kind = all.some((label) => isFirstIssueLabel(label?.name)) ? "Good first issue" : "Issue";
  const embed = itemEmbed(`${kind} #${issue.number}: ${issue.title ?? ""}`, issue);
  const labels = all
    .map((label) => clean(label?.name, MAX_TITLE))
    .filter((name) => name !== "");
  if (labels.length > 0) {
    embed.fields = [{ name: "Labels", value: truncate(labels.join(", "), MAX_FIELD) }];
  }
  return [{ embeds: [embed] }];
}

function answeredMessages(payload) {
  const { discussion, answer } = payload;
  if (!discussion || !answer || isBotUser(answer.user)) return [];
  const embed = {
    title: clean(`Answered: ${discussion.title ?? ""}`, MAX_TITLE),
    color: COLOUR,
    author: authorOf(answer.user),
  };
  const url = [answer.html_url, discussion.html_url].find(isGitHubUrl);
  if (url) embed.url = url;
  if (typeof discussion.user?.login === "string" && discussion.user.login !== "") {
    embed.fields = [{ name: "Question by", value: clean(discussion.user.login, MAX_FIELD) }];
  }
  const when = [answer.created_at, discussion.answer_chosen_at].find(
    (value) => typeof value === "string",
  );
  if (when) embed.timestamp = when;
  return [{ embeds: [embed] }];
}

function discussionMessages(payload) {
  if (payload.action === "answered") return answeredMessages(payload);
  const discussion = payload.discussion;
  if (payload.action !== "created" || !discussion || isBotUser(discussion.user)) return [];
  const category = discussion.category;
  const label = category?.slug === "q-a" ? "Question" : "Discussion";
  const embed = itemEmbed(`${label}: ${discussion.title ?? ""}`, discussion);
  if (typeof category?.name === "string" && category.name !== "") {
    embed.fields = [{ name: "Category", value: clean(category.name, MAX_FIELD) }];
  }
  return [{ embeds: [embed] }];
}

export function messagesFor(eventName, payload, repo) {
  if (eventName === "release") return releaseMessages(payload ?? {});
  if (eventName === "push") return pushMessages(payload ?? {}, repo);
  if (eventName === "issues") return issueMessages(payload ?? {});
  if (eventName === "discussion") return discussionMessages(payload ?? {});
  return [];
}

// Turns the test build marker into a mention of the Testers role, or drops it when there's no role.
export function withTestersPing(messages, roleId) {
  return messages.map(({ pingTesters, ...message }) => {
    if (!pingTesters || !roleId) return message;
    return { ...message, content: `<@&${roleId}>`, mentions: { roles: [roleId] } };
  });
}

// announced is the highest milestone already posted, or undefined on the first run.
export function planStarPost(stars, announced, repo) {
  const reached = STAR_MILESTONES.filter((milestone) => milestone <= stars);
  const highest = reached.length > 0 ? reached[reached.length - 1] : 0;
  if (announced === undefined) return { post: null, announced: highest };
  if (highest <= announced) return { post: null, announced };
  const embed = {
    title: `OrielOS has ${highest.toLocaleString("en-GB")} stars on GitHub`,
    description: "Thank you to everyone who starred it.",
    url: `https://github.com/${repo}/stargazers`,
    color: COLOUR,
  };
  return { post: { embeds: [embed] }, announced: highest };
}

// pulls is newest first; bookmark is the highest number already handled, or null on the first run.
export function planPullPosts(pulls, bookmark) {
  const numbers = pulls.map((pull) => pull.number).filter(Number.isInteger);
  const highest = Math.max(0, ...numbers);
  if (bookmark === null) return { posts: [], bookmark: highest };
  const posts = pulls
    .filter((pull) => Number.isInteger(pull.number) && pull.number > bookmark && !isBotUser(pull.user))
    .sort((a, b) => a.number - b.number)
    .map((pull) => {
      const kind = pull.draft ? "Draft pull request" : "Pull request";
      return { embeds: [itemEmbed(`${kind} #${pull.number}: ${pull.title ?? ""}`, pull)] };
    });
  return { posts, bookmark: Math.max(bookmark, highest) };
}

export async function sendPosts(rest, feed, messages) {
  for (const { mentions, crosspost: wantsCrosspost, ...body } of messages) {
    const sent = await sendMessage(rest, feed.id, body, mentions);
    if (wantsCrosspost === true && feed.type === 5) {
      try {
        await crosspost(rest, feed.id, sent.id);
      } catch {
        // Crossposting is a bonus; the message is already in the channel.
      }
    }
  }
}
