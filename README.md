# AIetherPanel-Strap

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![GitHub Repo Size](https://img.shields.io/github/repo-size/matthewxmurphy/AIetherPanel-Strap)
![GitHub Last Commit](https://img.shields.io/github/last-commit/matthewxmurphy/AIetherPanel-Strap)

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
- https://aetherpanel.com
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

First bootstrap from a fresh node:

```bash
curl -fsSL https://raw.githubusercontent.com/matthewxmurphy/AIetherPanel-Strap/main/install/bootstrap.sh | sudo bash -s -- \
  --profile hybrid \
  --admin-user mmurphy
```

Repair or re-apply the shared host baseline later if needed:

```bash
curl -fsSL https://raw.githubusercontent.com/matthewxmurphy/AIetherPanel-Strap/main/install/aetherpanel-host-apply.sh | sudo bash -s -- \
  --profile hybrid \
  --operator-user mmurphy
```
