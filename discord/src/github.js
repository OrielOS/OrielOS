// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import { readFile } from "node:fs/promises";

const API = "https://api.github.com";
const MAX_PAGES = 10;
const MAX_FLOW_SECONDS = 900;
const DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code";

export function mask(value) {
  console.log(`::add-mask::${value}`);
}

export function isHuman(entry) {
  return (
    entry !== null &&
    typeof entry === "object" &&
    Number.isInteger(entry.id) &&
    typeof entry.login === "string" &&
    entry.login !== "" &&
    entry.type !== "Bot" &&
    !entry.login.endsWith("[bot]")
  );
}

export function nextLink(header) {
  if (!header) return null;
  for (const part of header.split(",")) {
    const match = /^\s*<([^>]*)>\s*;(.*)$/.exec(part);
    if (match && /;?\s*rel="?next"?\s*(;|$)/.test(`;${match[2]}`)) {
      return match[1];
    }
  }
  return null;
}

export function maintainersFromCodeowners(text) {
  let owners = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (line === "" || line.startsWith("#")) continue;
    const [pattern, ...rest] = line.split(/\s+/);
    if (pattern !== "*") continue;
    owners = [];
    for (const token of rest) {
      if (token.startsWith("#")) break;
      if (/^@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(token)) {
        owners.push(token.slice(1).toLowerCase());
      }
    }
  }
  return owners;
}

export async function readMaintainers(file) {
  try {
    return maintainersFromCodeowners(await readFile(file, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
}

function apiHeaders(token) {
  const headers = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "OrielOS-Discord",
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

export async function fetchContributorIds(repo, token, fetchFn = fetch) {
  const ids = [];
  let url = `${API}/repos/${repo}/contributors?per_page=100`;
  for (let page = 0; url && page < MAX_PAGES; page += 1) {
    const response = await fetchFn(url, { headers: apiHeaders(token) });
    if (response.status === 204) break;
    if (!response.ok) {
      throw new Error(`GitHub answered ${response.status} for the contributors list.`);
    }
    const json = await response.json();
    if (!Array.isArray(json)) throw new Error("GitHub returned an unexpected contributors list.");
    ids.push(...json.filter(isHuman).map((entry) => entry.id));
    url = nextLink(response.headers.get("link"));
  }
  return ids;
}

export async function fetchGithubUser(token, fetchFn = fetch) {
  const response = await fetchFn(`${API}/user`, { headers: apiHeaders(token) });
  if (!response.ok) throw new Error(`GitHub answered ${response.status} for the profile.`);
  const { id, login } = await response.json();
  if (!Number.isInteger(id) || typeof login !== "string") {
    throw new Error("GitHub returned an unexpected profile.");
  }
  return { id, login };
}

async function postForm(url, fields, fetchFn) {
  const response = await fetchFn(url, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
      "User-Agent": "OrielOS-Discord",
    },
    body: new URLSearchParams(fields),
  });
  return response.json();
}

export async function requestDeviceCode(clientId, fetchFn = fetch) {
  const json = await postForm(
    "https://github.com/login/device/code",
    { client_id: clientId },
    fetchFn,
  );
  if (typeof json.device_code !== "string" || typeof json.user_code !== "string") {
    throw new Error("GitHub did not start the device flow.");
  }
  mask(json.device_code);
  mask(json.user_code);
  return {
    deviceCode: json.device_code,
    userCode: json.user_code,
    expiresIn: Math.min(Number(json.expires_in) || MAX_FLOW_SECONDS, MAX_FLOW_SECONDS),
    interval: Number(json.interval) || 5,
  };
}

// state: { interval in seconds, deadline and now in milliseconds }.
export function nextPollStep(state, response) {
  if (typeof response?.access_token === "string" && response.access_token !== "") {
    return { done: true, token: response.access_token };
  }
  const error = response?.error;
  if (error === "authorization_pending" || error === "slow_down") {
    if (state.now >= state.deadline) return { done: true, failure: "expired" };
    return { done: false, interval: state.interval + (error === "slow_down" ? 5 : 0) };
  }
  return { done: true, failure: typeof error === "string" ? error : "unknown" };
}

const defaultSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Resolves to the user token, or null when the member did not authorise in time.
export async function waitForToken(
  clientId,
  flow,
  { fetchFn = fetch, sleep = defaultSleep, now = Date.now } = {},
) {
  const deadline = now() + flow.expiresIn * 1000;
  let interval = flow.interval;
  for (;;) {
    await sleep(interval * 1000);
    let response;
    try {
      response = await postForm(
        "https://github.com/login/oauth/access_token",
        { client_id: clientId, device_code: flow.deviceCode, grant_type: DEVICE_GRANT },
        fetchFn,
      );
    } catch {
      return null;
    }
    const step = nextPollStep({ interval, deadline, now: now() }, response);
    if (step.done) {
      if (step.token) {
        mask(step.token);
        return step.token;
      }
      return null;
    }
    interval = step.interval;
  }
}
