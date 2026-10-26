# Contributing to OrielOS

Thank you for helping with OrielOS. This page explains how to report problems, suggest ideas and send changes. Please also read the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting bugs and proposing features

- **Questions** belong in the [Q&A](https://github.com/ncjsvr/OrielOS/discussions/categories/q-a) category of GitHub Discussions, and **open-ended ideas** in the [General](https://github.com/ncjsvr/OrielOS/discussions/categories/general) category. Issues are kept for actionable reports.
- **Bugs, game compatibility, hardware support and feature requests** use the issue forms. Choose the form that fits when you open a new issue, and fill in every required field. Search existing issues first.
- **Security problems** must not be reported in public. Follow [SECURITY.md](SECURITY.md).
- **Live chat** happens on [the official OrielOS Discord server](https://discord.gg/RnpZYaKbHA), the only one the project runs. Decisions are made on GitHub, so write anything that matters up as an issue, a discussion or a pull request.

## Contributing code

1. Fork the repository, or create a branch if you have write access.
2. Name the branch `<type>/<slug>`, for example `feat/start-menu` or `fix/updater-restart`.
3. Make one logical change per pull request. Small, focused pull requests are reviewed faster.
4. Write commit messages and the pull request title in [Conventional Commits](https://www.conventionalcommits.org/) form, for example `feat: add the Win+V clipboard history`. Pull requests are squash-merged, so the title becomes the commit message on `main`.
5. Sign off every commit with `git commit -s`. This adds a `Signed-off-by:` line with your name and email, and certifies the [Developer Certificate of Origin](https://developercertificate.org/). CI checks it. There is no contributor licence agreement.
6. Before you push, run `tools/preflight.sh`. It runs the checks CI runs on a pull request: that the pinned images and downloads in `image/pins.env` still exist, that every commit is signed off with a Conventional Commit subject, `tools/lint.sh`, and `tools/test-apps.sh` when the change touches anything the app build reads.
7. Open the pull request against `main` and complete the template. The maintainer reviews and merges every pull request.

### Files only the maintainer changes

Some files decide how the project is run, what the OS image trusts and what CI does with its secrets. A pull request from anyone but the maintainer that changes one of them is closed automatically, and its `protected-files` check fails. To suggest a change to one of these files, open an issue.

- `.github/`: the workflows, the code owners (who also get the Maintainer role on Discord), Dependabot, the Sponsor button, and the issue and pull request templates.
- `discord/`: the Discord bot, which runs with the bot's token.
- `image/keys/`, `image/module-signers.txt` and `image/pins.env`: the package signing keys, the allowed kernel module signers, and the pinned inputs the image is built from.
- `LICENSE`, `docs/LICENSE`, `README.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `GOVERNANCE.md`, `SECURITY.md`, `SUPPORT.md` and `VERSION`.

The check's list is in `.github/workflows/protected-files.yml`. Dependabot's dependency updates are allowed.

### Building, linting and testing

All tools run inside Linux or WSL2. An image build or VM test takes tens of gigabytes while it runs, and they run one at a time; `tools/clean.sh` frees what's left afterwards.

- `tools/check-env.sh` checks that the machine can build and boot-test the image.
- `tools/install-lint-tools.sh` installs the pinned linters once; `tools/lint.sh` then runs all of them.
- `tools/test-apps.sh` builds and tests the OrielOS apps.
- `tools/preflight.sh` runs everything CI checks on a pull request, before you push.
- `tools/build-image.sh` builds the image locally.
- `tests/boot-test.sh` boot-tests the image under QEMU/KVM.

CI runs the linters and checks on every pull request, and it must pass before a change is merged. Checks that a change can't affect pass without running, so a pull request that only changes documentation or the website doesn't wait for the app build.

New functionality comes with automated tests in the same pull request: unit tests beside the app's code, a check in `tests/` for the image, or a test in the `test/` folder of the website or the Discord bot. A bug fix adds a test that fails without the fix, where that's practical. Say in the pull request how you tested the change.

### Code style

- `.editorconfig` and `.clang-format` define the formatting; use an editor that honours them.
- Shell scripts pass `shellcheck` and `shfmt -i 4 -ci`.
- QML passes `qmllint`.
- Every user-visible string goes through KI18n so that it can be translated.

## Documentation

User documentation lives in `docs/`, and the repository's wiki is generated from it each time it changes. To improve a page, change its file in `docs/` in a pull request; edits made on the wiki are lost.

## Artwork

Artwork must be original, or under a compatible licence with the author and licence recorded alongside it. Nothing owned by Microsoft may be used: no logos, fonts, icons, sounds or wallpapers.

## Licensing of contributions

Contributions are licensed under the same terms as the project (inbound equals outbound). Code and configuration are `GPL-3.0-or-later`. Documentation in `docs/` and artwork in `artwork/` are `CC BY-SA 4.0`. By signing off a commit you confirm you have the right to contribute it under those terms.
