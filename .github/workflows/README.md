# Workflows: where they run

The jobs that build and test OrielOS run on [Blacksmith](https://www.blacksmith.sh/)'s runners,
which boot the same Ubuntu 24.04 image as GitHub's and support KVM, so the smoke test's VM runs
there too. Everything else stays on GitHub's own runners.

| Runs on Blacksmith | Stays on GitHub's runners |
|---|---|
| Image: `build` (the image build and its smoke test in a VM) | Image: `publish` and `notes` |
| Installer: `build` | Installer: `publish` |
| Apps: `apps` (build and test the apps) | Lint, DCO, Protected files, Scorecard |
| | Promote, Withdraw, Testing release, Mirror |
| | Website, Wiki, Discord |

Jobs that hold the signing key or publish (Image and Installer `publish`, Promote, Withdraw) stay
on GitHub's runners, as do short jobs that a faster machine wouldn't speed up.

## Choosing the runner

The three Blacksmith jobs pick their runner with one expression:

```yaml
runs-on: ${{ github.event.pull_request.head.repo.fork && 'ubuntu-24.04' || vars.BUILD_RUNNER || 'blacksmith-2vcpu-ubuntu-2404' }}
```

- A pull request from a fork always runs on GitHub's `ubuntu-24.04`, so outside contributions
  never use the project's Blacksmith minutes.
- The repository variable `BUILD_RUNNER` (Settings, Secrets and variables, Actions, Variables)
  overrides the runner for all three jobs at once, with no change to the workflows. Set it to
  `ubuntu-24.04` to move every build back to GitHub's runners, or to a larger Blacksmith size such
  as `blacksmith-4vcpu-ubuntu-2404`. Delete it to return to the default.
- Otherwise the job runs on `blacksmith-2vcpu-ubuntu-2404` (2 vCPUs, 8 GB memory, 80 GB disk).

Blacksmith counts usage in 2 vCPU minutes: a minute on a 4 vCPU runner counts as two, on 8 vCPUs
as four. The image and smoke test steps print the disk space left after they finish, which shows
whether a size's disk is big enough.
