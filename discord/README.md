# discord

The bot for [the official OrielOS Discord server](https://discord.gg/RnpZYaKbHA): it posts releases, merges, issues, discussions and pull requests, and gives members who link their GitHub account the Maintainer and Contributor roles. It has no server and never stays connected to Discord; it runs only as short GitHub Actions jobs.

## What it does

- **Posts.** When a release is published, a change is merged into `main`, or an issue or discussion is opened, it posts to `#github-feed`. New pull requests are found by the scheduled run, so they appear within about ten minutes. Only full releases ping @everyone and are crossposted if the channel is an announcement channel; everything else never pings and is not crossposted. Issue and discussion text is never posted, only the title, author, labels or category.
- **Roles.** Every 10 minutes it gives each linked member the Maintainer and Contributor roles that match GitHub, and takes them away when that stops being true.

## Linking

1. The about message in `#about` carries the bot's 🔗 reaction. Click it.
2. The next run sends you a direct message with a code. Open https://github.com/login/device and enter it. Allow direct messages from server members first.
3. The bot reads your public GitHub profile once, then forgets the token. The OAuth app asks for no scopes.

Remove your 🔗 reaction, or leave the server, to unlink. The bot then removes the roles it gave you. Links remember the message they were made on, so if the link message is ever replaced, existing links stay; react on the new message to be able to unlink there.

Only your Discord account ID, your GitHub account ID and your GitHub login are stored, as messages in a private `#bot-state` channel on the Discord server. Nothing personal goes into this repository.

## Where the roles come from

- **Maintainer:** the owners of the `*` rule in `.github/CODEOWNERS`. Teams and email addresses are skipped.
- **Contributor:** GitHub's contributors list for this repository, with bots left out. It is the same list orielos.org shows.

The roles carry no permissions, and only the bot gives them.

## Discord server setup

- **Channels:**
  - the link channel (`LINK_CHANNEL`, default `about`), holding the message members react to;
  - `#github-feed` (`CHANNEL_FEED`), for releases, merges, issues, discussions and pull requests;
  - `#bot-state` (`CHANNEL_STATE`), a private channel only the bot can see, where links are stored;
  - `#mod-log` (`CHANNEL_LOG`), optional: if it exists, every link and role change is logged there.
  Each setting takes a channel name or a channel ID; IDs keep working when a channel is renamed. The workflow sets the IDs of the official server's `#about` and `#github-feed`.
- **The link message.** Set `LINK_MESSAGE` to the ID of an existing message, such as the about message, and the bot adds its 🔗 reaction to it. Without it, the bot posts its own message in the link channel.
- **Roles,** found by name without regard to case: `Maintainer` and `Contributor`. The bot's own role sits above them.
- **The bot's permissions:** View Channels, Send Messages, Embed Links, Read Message History, Add Reactions and Manage Roles. In the link channel it also needs Manage Messages, to remove reactions. In `#github-feed` it also needs Mention @everyone, @here and All Roles, for release pings.
- **Members** must lack Add Reactions in the link channel, so they can only click the existing 🔗.

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
