# AIetherPanel-Strap Copilot Instructions

## Repo purpose
- This repo is the public stage-one/bootstrap and lightweight install source for AletherPanel.
- It is not the full Filament controller repo.
- Its job is to help a fresh server get onto Tailscale and then hand off to the second-stage installer/UI flow.

## Architecture rules
- Keep bootstrap logic lean and easy to audit.
- Stage one should install the minimum needed to bring Tailscale up.
- Stage two should come from the tailnet source and install the host baseline and local bootstrap UI.
- Do not turn this repo into the full control panel.
- `50000/tcp` is reserved for controller-to-server traffic over Tailscale only.
- Do not add public firewall assumptions for the control lane.

## Product rules
- Public/customer websites are not served from this repo.
- The visible controller belongs to the Filament app in the main AletherPanel repo.
- The local `lighttpd` surface is controller/bootstrap only.
- Do not add `phpMyAdmin`.
- Mail-role nodes use `iRedMail` and keep their own mail UI.

## Deployment rules
- Keep the installer output small and practical.
- Composer and heavy build tooling stay local in the main project flow.
- Only ship what the remote host actually needs to run the bootstrap or second-stage install.
- Favor idempotent shell steps and clear printed next commands.
