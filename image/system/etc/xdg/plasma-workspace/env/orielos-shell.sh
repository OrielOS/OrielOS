# shellcheck shell=sh
# Sourced by Plasma when a session starts. Makes OrielOS's own shell, org.orielos.desktop, the
# fallback whenever a user's plasmashellrc has an empty ShellPackage, which applying a global theme
# in Settings can write; plasmashell and the lock screen then fall back to PLASMA_DEFAULT_SHELL
# instead of /etc/xdg/plasmashellrc. A user's own non-empty ShellPackage still wins.
PLASMA_DEFAULT_SHELL=org.orielos.desktop
export PLASMA_DEFAULT_SHELL
