# Bounded stage-two integrity barrier

This change addresses the bootstrap download boundary from APP-17
([developer-standards#28](https://github.com/matthewxmurphy/developer-standards/issues/28)).
It does not establish release signing or qualify a complete installation.
Start with a bootstrap script obtained through a trusted, reviewed channel;
a `curl .../main/install/bootstrap.sh | sudo bash` command does not authenticate
that initial bootstrap script. No historical release files or versions change.

## Pre-mutation OS and tool admission

Before downloads or either mode's seven host-preparation helpers, bootstrap now
requires Bash4 or later, a readable/unambiguous exact Ubuntu `ID` in fixed
`/etc/os-release`, and its existing required commands. OS-ID admission reads the
metadata as data, not shell. The existing later Tailscale helper still sources
`/etc/os-release` for its repository codename, unchanged; this correction does
not qualify that helper/vendor chain. There is no caller-supplied admission
OS-file override. ID_LIKE alone,
duplicate/missing/malformed/non-Ubuntu ID and missing tools stop before host
preparation. Stage-two mode additionally requires sha256sum and staging utilities;
those dependencies are not installed after partial account/SSH changes.

This matches the existing Ubuntu-only source contract; it does not qualify any
Ubuntu release/version, kernel, architecture, package source or native install.
Tailscale itself can still be installed by its existing helper after admission.
SSH/operator policy and the pinned stage-two installer/helper bytes are unchanged.

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

The17-method fixture requires the reviewed isolated launcher, a reviewed cached
immutable Linux image with qualified Bash>=4/Python/utilities, a local user-owned
Docker Unix socket and an unprivileged operator. It never pulls or starts a daemon.
Review exact source and launcher before first execution. Use fresh private artifact
directories outside source; do not substitute a production endpoint. First obtain
version/hash metadata only, with no source mount or tests:

```sh
# Explicit reviewed local dependencies/paths, not mutable defaults.
/usr/bin/env -i PATH=/usr/bin:/bin /absolute/qualified/python -I -S -B tests/run_bootstrap_offline.py \
  --docker /absolute/qualified/docker --socket unix:///approved/local/socket \
  --image sha256:<reviewed-cached-image-id> \
  --evidence-dir /new/private/qualification --qualify
# After independent review of receipt.json and the frozen source tree:
/usr/bin/env -i PATH=/usr/bin:/bin /absolute/qualified/python -I -S -B tests/run_bootstrap_offline.py \
  --docker /absolute/qualified/docker --socket unix:///approved/local/socket \
  --image sha256:<same-image-id> --qualification /private/qualification/receipt.json \
  --tree <reviewed-git-index-tree> --expect-tests 17 --evidence-dir /new/private/offline-run
```

The placeholders deliberately do not execute as a working release recipe.
Source exports are ten explicit index paths, mounted read-only without a writable
alias. Only new owned home/tmp/sentinels are writable. The container is nonroot,
network-none, read-only-root, capability-free with no privilege escalation; there
is no host home/socket/project mount. Host and child environments are sanitized;
Python runs isolated without site/bytecode and Bash has no startup files. Denial
sentinels fail any unexpected host/network command. The launcher binds executable,
image, source/stub hashes and unique container name/ID, verifies its owner label
and removes only that owned ID on normal exit/failure/timeout. An uncertain cleanup
is a failure, never a success receipt. No test/native acceptance is asserted by
these instructions before an actual reviewed run.

The tests source only bootstrap function definitions, replace every host-preparation
helper, replace curl with a local fixture reader, and replace the stage-two executor
with a marker recorder. **They never execute the stage-two script or its native
helpers.** Synthetic missing-payload bytes are intentionally not valid service or
archive contents. Tests prove rejection before host preparation/execution for
tampered or truncated assets, peer manifests, unknown installer graphs, OS/tool rejection in both modes before downloads/preparation, mutable
GitHub refs, unsafe overrides, missing assets, and download failures. They also
verify the audited-file success path reaches only the stub runner, carries the
source binding, and cleans up after runner failure.

No installer, provider API, real node, package installation, or service configuration
was exercised. Package repositories, external vendor downloads, the initial
bootstrap distribution channel, and the operational correctness of the missing
payloads remain outside this bounded barrier. APP-17 is only partially addressed
until an authenticated complete release/distribution contract exists and is tested.


## Source maintenance and standards adoption

Maintained by Matthew X Murphy, https://MatthewxMurphy.com;
https://builtnotbegged.com. Existing ownership, SSH/operator policy, release
identities and licensing/distribution remain unchanged. No new license grant,
release, deployment or complete #28 acceptance is introduced. The shared
[engineering SOP](https://github.com/matthewxmurphy/developer-standards) applies.
Adoption remains partial: scoped source/tests/runbook are present, while complete
metadata/licenses/notices, portable checker distribution/integration, remote
CI/protection and native release/rollback qualification remain separate. Do not
vendor the internally restricted checker into public source without an
applicable redistribution grant. A fixture receipt is not OS/install acceptance
or proof that real backup/rollback works.
