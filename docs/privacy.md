# Privacy

OrielOS collects nothing about you. It has no telemetry, no account, no advertising ID and no crash reports sent anywhere, and it never sends your files, your activity or what you install to anyone.

It does connect to the internet to keep itself and your apps up to date. This page lists every place OrielOS's own parts connect to, and why. Apps you install, such as Steam or Firefox, have their own privacy policies, listed at the end.

## Where OrielOS connects, and why

| Where | What for | When |
|---|---|---|
| `ghcr.io` (GitHub's container registry), `ghcr.io/orielos/orielos` | Checking for and downloading OrielOS updates, with their signatures | About 10 minutes after starting, then every 6 hours; not on a metered connection or while updates are paused |
| `dl.flathub.org` and Flathub's mirrors | Installing and updating apps from the Store, including Firefox on the first start and the NVIDIA driver's add-ons for apps | When you install an app, and in the background for app updates unless you turn them off; not on a metered connection |
| `raw.githubusercontent.com/OrielOS/OrielOS` | The newest list of Windows programs Run this app knows (which ones the Store has, and Microsoft Store packages) | When you open a Windows program with Run this app |
| `raw.githubusercontent.com/AreWeAntiCheatYet` | The newest list of games with anti-cheat, for Game Settings' Will it run? | When you open Game Settings |
| `geoip.fedoraproject.org` | Guessing your time zone during the first-run setup. It sends nothing but your connection's address, which any website sees | Once, during setup, when you're online |
| `fedoraproject.org/static/hotspot.txt` | Checking whether the network reaches the internet, or needs a sign-in page first, as on hotel or café Wi-Fi (NetworkManager, as on Fedora) | Every 5 minutes while connected |
| `2.fedora.pool.ntp.org` | Setting the clock (chrony, as on Fedora) | Now and then while connected |
| `github.com` and `repo.steampowered.com` (through umu-launcher) | Downloading GE-Proton and the Steam Linux Runtime the first time you run a Windows program | Once per version, when Run this app first needs them |

Firmware updates through Settings use the Linux Vendor Firmware Service (`cdn.fwupd.org`) only when you check for them; OrielOS doesn't check in the background.

Every connection uses HTTPS except NetworkManager's connectivity check, which is plain HTTP by design (it has to see whether a café's sign-in page gets in the way) and carries nothing about you.

KDE's optional feedback to KDE is not part of OrielOS.

## Apps with their own policies

Apps you install from the Store are made by others, and their own privacy policies apply. Among those OrielOS points you to:

- **Firefox**, installed on the first start: [Mozilla's Firefox Privacy Notice](https://www.mozilla.org/privacy/firefox/)
- **Steam**: [Valve's Privacy Policy](https://store.steampowered.com/privacy_agreement/)
- **Microsoft Edge**, **Discord**, **Spotify** and the game stores' launchers each have their own policy on their makers' websites.

## The website

[orielos.org](https://orielos.org) has no analytics, no cookies and no requests to anyone else's servers. GitHub Pages hosts it and Cloudflare sits in front of it, so both handle your requests as any host does. Search engines' webmaster tools report to OrielOS only on OrielOS's place in their own search results.

## Checking for yourself

OrielOS is open source: everything above can be read in [its code](https://github.com/OrielOS/OrielOS). Tools such as Wireshark, from the Store, show every connection a computer makes.
