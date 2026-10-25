# discord

The OrielOS Discord bot: it posts releases and merges, and gives members who link their GitHub account the Maintainer and Contributor roles. It has no server and never stays connected to Discord; it runs only as short GitHub Actions jobs.

## What it does

- **Posts.** When a release is published, or a change is merged into `main`, it posts to `#github-feed`. Posts never ping anyone.
- **Roles.** Every 10 minutes it gives each linked member the Maintainer and Contributor roles that match GitHub, and takes them away when that stops being true.

## Linking

1. The bot keeps a message in `#welcome` with a 🔗 reaction. Click it.
2. The next run sends you a direct message with a code. Open https://github.com/login/device and enter it. Allow direct messages from server members first.
3. The bot reads your public GitHub profile once, then forgets the token. The OAuth app asks for no scopes.

Remove your 🔗 reaction, or leave the server, to unlink. The bot then removes the roles it gave you. If the 🔗 message is ever deleted, the bot posts a new one and existing links stay; react on the new message to be able to unlink there.

Only your Discord account ID, your GitHub account ID and your GitHub login are stored, as messages in a private `#bot-state` channel on the Discord server. Nothing personal goes into this repository.

## Where the roles come from

- **Maintainer:** the owners of the `*` rule in `.github/CODEOWNERS`. Teams and email addresses are skipped.
- **Contributor:** GitHub's contributors list for this repository, with bots left out. It is the same list orielos.org shows.

The roles carry no permissions, and only the bot gives them.

## Discord server setup

- Channels, found by exact name: `#welcome`, `#bot-state` (private, visible only to the bot), `#mod-log` and `#github-feed`.
- Roles, found by name without regard to case: `Maintainer` and `Contributor`.
- The bot's own role sits above `Maintainer` and `Contributor`.
- The bot's permissions: View Channels, Send Messages, Embed Links, Read Message History, Add Reactions and Manage Roles. It also needs Manage Messages in `#welcome` only, to remove reactions.
- Members must lack Add Reactions in `#welcome`, so they can only click the existing 🔗.

To use other names, set `CHANNEL_WELCOME`, `CHANNEL_STATE`, `CHANNEL_LOG`, `CHANNEL_FEED`, `ROLE_MAINTAINER` and `ROLE_CONTRIBUTOR`. If the bot is in more than one server, set `DISCORD_GUILD_ID`.

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
