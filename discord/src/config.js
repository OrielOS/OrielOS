// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

export const NOT_RUNNING_NOTICE =
  "::notice::DISCORD_TOKEN is not set, so the Discord bot is not running.";

export function readConfig(env) {
  const text = (name, fallback = "") => {
    const value = (env[name] ?? "").trim();
    return value === "" ? fallback : value;
  };
  return {
    token: text("DISCORD_TOKEN"),
    linkClientId: text("LINK_CLIENT_ID"),
    githubToken: text("GITHUB_TOKEN"),
    repo: text("GITHUB_REPOSITORY", "ncjsvr/OrielOS"),
    guildId: text("DISCORD_GUILD_ID"),
    names: {
      welcome: text("CHANNEL_WELCOME", "welcome"),
      state: text("CHANNEL_STATE", "bot-state"),
      log: text("CHANNEL_LOG", "mod-log"),
      feed: text("CHANNEL_FEED", "github-feed"),
      maintainer: text("ROLE_MAINTAINER", "Maintainer"),
      contributor: text("ROLE_CONTRIBUTOR", "Contributor"),
    },
  };
}

export function isEnabled(config) {
  return config.token !== "";
}
