# Bounded stage-two integrity barrier

This change addresses the bootstrap download boundary from APP-17
([developer-standards#28](https://github.com/matthewxmurphy/developer-standards/issues/28)).
It does not establish release signing or qualify a complete installation.
Start with a bootstrap script obtained through a trusted, reviewed channel;
a `curl .../main/install/bootstrap.sh | sudo bash` command does not authenticate
that initial bootstrap script. No historical release files or versions change.

## What the bootstrap verifies

The default stage-two source is the full immutable source commit
`25a19882d204dfba392090f84d563d8df9d4038c` in the public
`matthewxmurphy/AIetherPanel-Strap` repository. This is a source identity, not a
new release. The correct tracked stage-two filename is
`install/aetherpanel-install.sh` (without `ai`). Its reviewed SHA256 is:

```text
1f0c5d6c75e782c8ffbe62c4e92c5063ab381bb1bb4e63fe4c40471c3b330b00
```

Before any bootstrap host preparation or stage-two execution, bootstrap downloads
and verifies that script, all five sourced `install/steps/*.sh` helpers,
`conf/lighttpd-controller.conf.template`, `ui/public/index.php`, and the two
required external payloads below. Fixed hashes for the tracked files are embedded
in the reviewed bootstrap. HTTPS-only downloads and redirects are required.
Failed downloads and hash mismatches stop the process. The verified files are
staged in a private temporary source tree so the audited installer discovers its
local helpers/templates/controller archive instead of fetching them again.
The selected source root and controller tag propagate to stage two. The temporary
tree is removed on normal exit or failure.

## Complete installation is still blocked

Neither audited repository contains these required payloads:

- `conf/aetherpanel-lighttpd.service.template`
- `controller/dist/controller-runtime/controller-ready-stable-livewire.tar.gz`

A reviewed complete payload and trusted SHA256 for **each** are still required.
The service template must match the intended service lifecycle; the controller
archive must match the installer's extraction/runtime contract. This change does
not invent either payload, a signing key, a release, or an expected hash. Without
these trusted inputs, `--run-stage-two` deliberately stops **before** Tailscale,
operator accounts, SSH configuration, package repositories, or stage two change
the host. Prep-only mode retains its existing behavior and still changes the host.

These externally supplied hashes must come from the operator's trusted review or
release channel. Downloading a checksum or manifest from the same mutable peer
as the payload does not authenticate it. The historical `releases/latest`
manifest is not a trust anchor and is never used by this barrier.

## Custom mirrors and tailnet-only sources

Custom HTTPS mirrors remain supported for the **same audited script and dependency
graph**. Supply the explicit stage-two hash above plus trusted hashes for the two
missing payloads. A different installer needs a separate dependency-graph review;
its arbitrary hash is intentionally not accepted. GitHub raw source roots must
contain a full immutable commit, never a branch or tag. Source URLs cannot carry
credentials, query strings, fragments, or relative path components. All required
relative paths and tracked file bytes must match the audited source. A controller
bundle tag override must be a single safe path component and have its corresponding
operator-trusted archive digest.

Verification now precedes Tailscale bring-up. A private mirror available only over
the tailnet therefore requires an already connected host, or this explicit
**two-step** flow. The commands below are operator instructions, not test commands;
they were not executed during this change:

```bash
# Step 1: reviewed local bootstrap; prep only, no --run-stage-two.
# This performs the existing host preparation, including Tailscale bring-up.
sudo bash ./install/bootstrap.sh --tailscale-authkey "$TAILSCALE_AUTHKEY"

# Step 2: after the mirror is reachable, verify all assets before stage two.
# Set these values from a trusted review/release channel, never a peer manifest.
export TRUSTED_SERVICE_SHA256='<reviewed 64-hex service-template digest>'
export TRUSTED_CONTROLLER_SHA256='<reviewed 64-hex controller-archive digest>'
sudo bash ./install/bootstrap.sh --run-stage-two \
  --stage-two-source-root 'https://mirror.example/reviewed-source' \
  --stage-two-sha256 '1f0c5d6c75e782c8ffbe62c4e92c5063ab381bb1bb4e63fe4c40471c3b330b00' \
  --stage-two-service-sha256 "$TRUSTED_SERVICE_SHA256" \
  --stage-two-controller-sha256 "$TRUSTED_CONTROLLER_SHA256" \
  --profile hybrid --node-name example-node
```

The placeholders deliberately fail validation. They are not real digests or a
working release recipe. Supply other required installation options from the
existing installer documentation. If an operator chooses a private GitHub mirror,
GitHub authentication/distribution still needs an approved contract; credentials
must not be embedded in the source URL.

## Offline verification and coverage limit

```bash
bash -n install/bootstrap.sh
python3 -m unittest discover -s tests -p 'test_bootstrap_integrity.py' -v
```

The tests source only bootstrap function definitions, replace every host-preparation
helper, replace curl with a local fixture reader, and replace the stage-two executor
with a marker recorder. **They never execute the stage-two script or its native
helpers.** Synthetic missing-payload bytes are intentionally not valid service or
archive contents. Tests prove rejection before host preparation/execution for
tampered or truncated assets, peer manifests, unknown installer graphs, mutable
GitHub refs, unsafe overrides, missing assets, and download failures. They also
verify the audited-file success path reaches only the stub runner, carries the
source binding, and cleans up after runner failure.

No installer, provider API, real node, package installation, or service configuration
was exercised. Package repositories, external vendor downloads, the initial
bootstrap distribution channel, and the operational correctness of the missing
payloads remain outside this bounded barrier. APP-17 is only partially addressed
until an authenticated complete release/distribution contract exists and is tested.
