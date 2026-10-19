# AIetherPanel-Strap

![License](https://img.shields.io/github/license/matthewxmurphy/AIetherPanel-Strap)
![GitHub Repo Size](https://img.shields.io/github/repo-size/matthewxmurphy/AIetherPanel-Strap)
![Last Commit](https://img.shields.io/github/last-commit/matthewxmurphy/AIetherPanel-Strap)

Public bootstrap installer for AIetherPanel by Matthew Murphy.

![AIetherPanel Logo](logo.png)

This repo is the small public install surface for AI Control Host and Net30 Hosting. It contains only the files needed to bootstrap the per-server AIetherPanel host baseline:

- `install/` bootstrap and step scripts
- `install/aetherpanel-host-apply.sh` repair and re-apply baseline helper
- `conf/` lighttpd template
- `ui/` node-local PHP/lighttpd surface
- `releases/latest/manifest.json`

The main private controller and broader project code stay in the private repos.

Primary domains:
- https://aietherpanel.com
- https://www.matthewxmurphy.com
- https://www.net30hosting.com

Common install profiles:
- `hybrid` for the current all-in-one controller/web/database nodes
- `controller` for a future dedicated control-panel host
- `application` for a website/application host without the controller role
- `mail-test` for the future testing mail host
- `dns` for a tiny DNS-only host

Security baseline:
- `fail2ban` installs locally on the node
- `CrowdSec` is handled remotely and is not installed by the node bootstrap

## Installation status and trusted entrypoint

Full stage-two installation is currently blocked: the audited source lacks the
required service template and controller archive. The integrity barrier requires
reviewed payloads and trusted digests and fails before host preparation without
them. Obtain the bootstrap itself through a trusted, reviewed source before
running it as root; the barrier cannot authenticate its own initial download.
Mutable-main download-and-execute recipes are not a trusted entrypoint.

See [the bounded integrity contract](docs/bootstrap-stage-two-integrity.md) for
exact missing inputs, custom mirrors, coverage limits, and the two-step flow when
a mirror requires Tailscale bring-up first. No full installation has been qualified.

After obtaining and reviewing a local copy, existing **prep-only** mode is:

```bash
sudo bash ./install/bootstrap.sh --profile hybrid --admin-user mmurphy
```

This command changes the host baseline, including Tailscale, operator access,
package repositories and SSH configuration. It does not run stage two. Only
proceed to `--run-stage-two` after completing the trusted payload requirements
in the linked contract.

The repair/re-apply helper is outside this bounded stage-two integrity barrier.
Obtain and review a local copy before separately choosing to run it:

```bash
sudo bash ./install/aetherpanel-host-apply.sh --profile hybrid --operator-user mmurphy
```
