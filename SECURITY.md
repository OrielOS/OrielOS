# Security policy

## Supported versions

OrielOS is in early development. Only the latest image build is supported, and fixes are made there.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately by either of these routes:

- GitHub private vulnerability reporting: open the **Security** tab of the repository and choose **Report a vulnerability**. This is the preferred route.
- Email `security@orielos.org`.

Please include:

- what is affected (component, image build tag from `bootc status`) and the impact you see;
- steps to reproduce, or a proof of concept;
- any logs, and your hardware if it matters;
- whether the problem is already public, and any deadline you are working to.

## What to expect

OrielOS has one maintainer, so these are best-effort targets:

- acknowledgement within 7 days;
- an initial assessment within 14 days;
- updates as the fix progresses.

## Coordinated disclosure

Please give the maintainer reasonable time to fix the problem before publishing details. Once a fix is released, the report is disclosed publicly with credit to the reporter, unless you prefer to stay anonymous.

## Scope

In scope: OrielOS's own code, apps and image configuration.

Out of scope: bugs in upstream projects such as Fedora, KDE, NVIDIA and Universal Blue. Report those to the upstream project; OrielOS will help where it can, for example by describing how the problem shows up on OrielOS.
