# discord

The bot for [the official OrielOS Discord server](https://discord.gg/RnpZYaKbHA): it posts what happens on GitHub, gives members who link their GitHub account the Maintainer and Contributor roles, and gives members the Testers, NVIDIA and AMD roles when they ask for them with a reaction. It has no server and never stays connected to Discord; it runs only as short GitHub Actions jobs.

## What it does

- **Posts** to `#github-feed`:
  - as they happen: published releases, merges into `main`, someone's first merged contribution, new issues, issues labelled `good first issue` after they were opened, new discussions, and questions marked as answered;
  - from the scheduled run, within about ten minutes: new pull requests, and star milestones (10, 25, 50, 100, 250 and on, each posted once).
  A full release pings @everyone; a pre-release is posted as a test build and pings the Testers role. Only releases are crossposted if the channel is an announcement channel; nothing else pings. Issue and discussion text is never posted, only the title, author, labels or category.
- **Roles.** Every 10 minutes it gives each linked member the Maintainer and Contributor roles that match GitHub, and takes them away when that stops being true.
- **Opt-in roles.** Members who react on the about message get a role, and lose it when they remove the reaction: 🧪 for Testers (pinged for test builds), 🟢 for NVIDIA and 🔴 for AMD (which graphics card they have). A member can have any of them. The bot adds each reaction only when its role exists.

## Linking

1. The about message in `#about` carries the bot's 🔗 reaction. Click it.
2. The next run sends you a direct message with a code. Open https://github.com/login/device and enter it. Allow direct messages from server members first.
3. The bot reads your public GitHub profile once, then forgets the token. The OAuth app asks for no scopes.

Remove your 🔗 reaction, or leave the server, to unlink. The bot then removes the roles it gave you. Links remember the message they were made on, so if the link message is ever replaced, existing links stay; react on the new message to be able to unlink there.

Only your Discord account ID, your GitHub account ID and your GitHub login are stored, as messages in a private `#bot-state` channel on the Discord server. Nothing personal goes into this repository.

## Where the roles come from

- **Maintainer:** the owners of the `*` rule in `.github/CODEOWNERS`. Teams and email addresses are skipped.
- **Contributor:** GitHub's contributors list for this repository, with bots left out. It is the same list orielos.org shows.

The roles carry no moderation powers, and only the bot gives them.

## Discord server setup

- **Channels:**
  - the link channel (`LINK_CHANNEL`, default `about`), holding the message members react to;
  - `#github-feed` (`CHANNEL_FEED`), for releases, merges, issues, discussions and pull requests;
  - `#bot-state` (`CHANNEL_STATE`), a private channel only the bot can see, where links are stored;
  - `#mod-log` (`CHANNEL_LOG`), optional: if it exists, every link and role change is logged there.
  Each setting takes a channel name or a channel ID; IDs keep working when a channel is renamed. The workflow sets the IDs of the official server's `#about` and `#github-feed`.
- **The link message.** Set `LINK_MESSAGE` to the ID of an existing message, such as the about message, and the bot adds its 🔗 reaction (and 🧪, 🟢 and 🔴 for the opt-in roles that exist) to it. Without it, the bot posts its own message in the link channel.
- **Roles,** found by name without regard to case: `Maintainer` and `Contributor`, and optionally `Testers` (`ROLE_TESTERS`), `NVIDIA` (`ROLE_NVIDIA`) and `AMD` (`ROLE_AMD`). The bot's own role must sit above all of them, or Discord won't let it give them.
- **The bot's permissions:** View Channels, Send Messages, Embed Links, Read Message History, Add Reactions and Manage Roles. In the link channel it also needs Manage Messages, to remove reactions. In `#github-feed` it also needs Mention @everyone, @here and All Roles, for the release and Testers pings.
- **Members** must lack Add Reactions in the link channel, so they can only click the existing 🔗, 🧪, 🟢 and 🔴.

If the bot is in more than one server, set `DISCORD_GUILD_ID`.

## GitHub setup

- A GitHub OAuth app with **Enable Device Flow** ticked and no scopes.
- An environment named `discord` that only `main` can use. It holds the `DISCORD_TOKEN` secret (the bot token) and the `LINK_CLIENT_ID` variable (the OAuth app's client ID).

Until `DISCORD_TOKEN` is set, the jobs do nothing. Without `LINK_CLIENT_ID`, existing links still sync but new members are not linked.

The bot token lives only in that environment's secret. GitHub encrypts it, hides it in logs and never passes it to workflows started from forks. The logs contain counts only, never names, IDs or codes.

## Tests

You need Node.js 22. From this folder:

```bash
npm ci
npm test
```

The tests use no network and no token.
