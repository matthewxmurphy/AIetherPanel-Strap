"""Offline bootstrap boundary tests: no installer or host helper is executed."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
BOOTSTRAP = REPO / "install/bootstrap.sh"
PINNED = "https://raw.githubusercontent.com/matthewxmurphy/AIetherPanel-Strap/25a19882d204dfba392090f84d563d8df9d4038c"
INSTALLER = "install/aetherpanel-install.sh"
KNOWN_FILES = (
    INSTALLER,
    "install/steps/10-preflight.sh",
    "install/steps/20-packages.sh",
    "install/steps/30-tailscale.sh",
    "install/steps/40-panel-files.sh",
    "install/steps/50-services.sh",
    "conf/lighttpd-controller.conf.template",
    "ui/public/index.php",
)
SERVICE = "conf/aetherpanel-lighttpd.service.template"
BUNDLE = "controller/dist/controller-runtime/controller-ready-stable-livewire.tar.gz"
# Deliberately not installable payloads. Only the runner stub sees these fixtures.
SERVICE_BYTES = b"offline service fixture; not a systemd unit\n"
BUNDLE_BYTES = b"offline bundle fixture; not an archive\n"

FAKE_DOWNLOAD = r'''
import json, os, pathlib, sys
args = sys.argv[1:]
url = next((arg for arg in args if arg.startswith("https://")), "")
root = os.environ["FAKE_SOURCE_ROOT"]
with open(os.environ["REQUEST_LOG"], "a") as stream:
    stream.write(json.dumps(args) + "\n")
required = {"--fail", "--silent", "--show-error", "--location", "--proto", "--proto-redir", "--connect-timeout", "--max-time", "--output"}
if not required.issubset(args) or args[args.index("--proto") + 1] != "=https" or args[args.index("--proto-redir") + 1] != "=https":
    sys.exit(97)
if not url.startswith(root + "/"):
    sys.exit(96)
relative = url[len(root) + 1:]
if relative == os.environ.get("FAIL_DOWNLOAD"):
    sys.exit(22)
path = pathlib.Path(os.environ["FIXTURE_ROOT"]) / relative
if not path.is_file():
    sys.exit(22)
destination = pathlib.Path(args[args.index("--output") + 1])
destination.write_bytes(path.read_bytes())
'''

FAKE_RUNNER = r'''
import hashlib, json, os, pathlib, sys
script = pathlib.Path(sys.argv[1])
root = script.parent.parent
files = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
         for path in root.rglob("*") if path.is_file()}
with open(os.environ["RUNNER_LOG"], "a") as stream:
    stream.write(json.dumps({"argv": sys.argv[1:], "files": files,
                            "source_root": os.environ.get("AETHERPANEL_INSTALL_SOURCE_ROOT"),
                            "bundle_tag": os.environ.get("AETHERPANEL_CONTROLLER_BUNDLE_TAG"),
                            "temporary_root": str(root.parent)}) + "\n")
sys.exit(int(os.environ.get("RUNNER_EXIT", "0")))
'''

# Source only function definitions, then replace every host-mutating helper and
# the stage-two executor. The actual stage-two script is never sourced or run.
HARNESS = r'''
source "$BOOTSTRAP_PATH"
require_root() { :; }
record_prep() { printf '%s\n' "$1" >> "$PREP_LOG"; printf 'prep:%s\n' "$1" >> "$PHASE_LOG"; }
bootstrap_os_id() { printf 'os\n' >> "$PHASE_LOG"; [ -f "$TEST_OS_RELEASE" ] && parse_os_release_id <"$TEST_OS_RELEASE"; }
bootstrap_command_available() { printf 'tool:%s\n' "$1" >> "$PHASE_LOG"; [ "$1" != "${TEST_MISSING_TOOL:-}" ]; }
install_tailscale() { record_prep install_tailscale; }
ensure_operator_user() { record_prep ensure_operator_user; }
resolve_ssh_pub_source() { record_prep resolve_ssh_pub_source; }
append_authorized_keys() { record_prep append_authorized_keys; }
ensure_tailscale_connected() { record_prep ensure_tailscale_connected; }
ensure_aietherpanel_apt_repo() { record_prep ensure_aietherpanel_apt_repo; }
harden_ssh() { record_prep harden_ssh; }
curl() { printf 'download\n' >> "$PHASE_LOG"; "$TEST_PYTHON" -I -S -B "$DOWNLOAD_STUB" "$@"; }
bash() { printf 'runner\n' >> "$PHASE_LOG"; "$TEST_PYTHON" -I -S -B "$RUNNER_STUB" "$@"; }
main "$@"
'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


class BootstrapIntegrity(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bootstrap-offline-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fixtures = self.root / "fixtures"
        for relative in KNOWN_FILES:
            destination = self.fixtures / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / relative, destination)
        for relative, data in ((SERVICE, SERVICE_BYTES), (BUNDLE, BUNDLE_BYTES)):
            destination = self.fixtures / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        (self.root / "download.py").write_text(FAKE_DOWNLOAD)
        (self.root / "runner.py").write_text(FAKE_RUNNER)
        if not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
            self.fail("Use the reviewed isolated outer launcher; no ambient Python startup")
        if os.getuid() == 0:
            self.fail("Offline fixtures must run as an unprivileged user")
        self.bash = os.environ["BOOTSTRAP_TEST_BASH"]
        if digest(Path(self.bash).read_bytes()) != os.environ["BOOTSTRAP_TEST_BASH_SHA256"]:
            self.fail("Bash executable differs from the qualified digest")
        self.env = {key: os.environ[key] for key in ("PATH", "HOME", "TMPDIR", "LANG")}
        (self.root / "os-release").write_text('ID="ubuntu"\n')
        self.env.update({
            "BOOTSTRAP_PATH": str(BOOTSTRAP),
            "FIXTURE_ROOT": str(self.fixtures),
            "FAKE_SOURCE_ROOT": PINNED,
            "TEST_PYTHON": sys.executable,
            "TEST_OS_RELEASE": str(self.root / "os-release"),
            "PHASE_LOG": str(self.root / "phases.txt"),
            "DOWNLOAD_STUB": str(self.root / "download.py"),
            "RUNNER_STUB": str(self.root / "runner.py"),
            "REQUEST_LOG": str(self.root / "requests.jsonl"),
            "RUNNER_LOG": str(self.root / "runner.jsonl"),
            "PREP_LOG": str(self.root / "prep.txt"),
        })
        self.complete = [
            "--run-stage-two",
            "--stage-two-service-sha256", digest(SERVICE_BYTES),
            "--stage-two-controller-sha256", digest(BUNDLE_BYTES),
        ]

    def run_bootstrap(self, args, extra_env=None):
        env = dict(self.env)
        env.update(extra_env or {})
        return subprocess.run([self.bash, "--noprofile", "--norc", "-c", HARNESS, "offline-bootstrap", *args],
                              env=env, text=True, capture_output=True, timeout=20)

    def records(self, name):
        path = self.root / name
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def assert_rejected_before_prep(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root / "prep.txt").exists(), "host-prep helper was called")
        self.assertEqual(self.records("runner.jsonl"), [], "stage-two executor was called")
        # Destinations are recorded before download; cleanup must also run on failure.
        for request in self.records("requests.jsonl"):
            partial = Path(request[request.index("--output") + 1])
            self.assertFalse(partial.exists())
            temporary_root = next(parent for parent in partial.parents
                                  if parent.name.startswith("aetherpanel-bootstrap."))
            self.assertFalse(temporary_root.exists(), "staged tree was not cleaned up")

    def test_unsupported_or_ambiguous_os_rejects_both_modes_before_any_effect(self):
        metadata = ['ID=debian\n', 'ID_LIKE=ubuntu\n', '', 'ID=ubuntu\nID=debian\n',
                    'ID=ubuntu\nID=ubuntu\n', 'ID="ubuntu\n', 'ID=\n',
                    f'ID=$(touch {self.root / "must-not-execute"})\n']
        for value in metadata:
            for args in ([], self.complete):
                with self.subTest(value=value, stage_two=bool(args)):
                    (self.root / "os-release").write_text(value)
                    result = self.run_bootstrap(args)
                    self.assert_rejected_before_prep(result)
                    self.assertEqual(self.records("requests.jsonl"), [])
                    self.assertFalse((self.root / "must-not-execute").exists())

    def test_missing_os_metadata_rejects_both_modes_before_any_effect(self):
        (self.root / "os-release").unlink()
        for args in ([], self.complete):
            self.assert_rejected_before_prep(self.run_bootstrap(args))
        self.assertEqual(self.records("requests.jsonl"), [])

    def test_quoted_ubuntu_id_is_parsed_as_data_and_preflight_precedes_effects(self):
        for value in ['ID=ubuntu\n', 'ID="ubuntu"\n', "ID='ubuntu'\n"]:
            with self.subTest(value=value):
                (self.root / "os-release").write_text(value)
                result = self.run_bootstrap(self.complete)
                self.assertEqual(result.returncode, 0, result.stderr)
                phases = (self.root / "phases.txt").read_text().splitlines()
                first_effect = next(n for n, phase in enumerate(phases) if phase == "download")
                self.assertEqual(phases[0], "os")
                self.assertTrue(all(phase.startswith("tool:") for phase in phases[1:first_effect]))
                self.assertIn("tool:sha256sum", phases[:first_effect])
                self.assertIn("tool:apt-get", phases[:first_effect])
                self.assertLess(first_effect, next(n for n, phase in enumerate(phases) if phase.startswith("prep:")))
                self.assertEqual(phases[-1], "runner")
                for name in ['phases.txt', 'prep.txt', 'requests.jsonl', 'runner.jsonl']:
                    (self.root / name).unlink()

    def test_each_missing_required_tool_rejects_before_download_or_preparation(self):
        common = 'id apt-get systemctl useradd usermod install touch chown chmod mktemp curl sed grep head diff mv date rm cat'.split()
        for args, tools in (([], common), (self.complete, common + ['sha256sum', 'mkdir', 'dirname', 'bash'])):
            for tool in tools:
                with self.subTest(stage_two=bool(args), tool=tool):
                    result = self.run_bootstrap(args, {"TEST_MISSING_TOOL": tool})
                    self.assert_rejected_before_prep(result)
                    self.assertIn('command unavailable: ' + tool, result.stderr)
                    self.assertEqual(self.records("requests.jsonl"), [])

    def test_prep_only_preserves_existing_flow_without_stage_two_downloads(self):
        result = self.run_bootstrap([])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len((self.root / "prep.txt").read_text().splitlines()), 7)
        self.assertEqual(self.records("requests.jsonl"), [])
        self.assertEqual(self.records("runner.jsonl"), [])

    def test_missing_payload_trust_inputs_fail_before_any_host_preparation(self):
        result = self.run_bootstrap(["--run-stage-two"])
        self.assert_rejected_before_prep(result)
        self.assertIn("lacks the service template and controller bundle", result.stderr)
        self.assertEqual(self.records("requests.jsonl"), [])

    def test_custom_source_requires_explicit_trusted_installer_hash(self):
        result = self.run_bootstrap(self.complete + ["--stage-two-source-root", "https://mirror.example/source"])
        self.assert_rejected_before_prep(result)
        self.assertIn("explicit trusted", result.stderr)

    def test_mutable_github_ref_and_source_override_aliases_cannot_bypass_binding(self):
        sha = digest((REPO / INSTALLER).read_bytes())
        for option in ("--stage-two-source-root", "--install-source-root"):
            with self.subTest(option=option):
                result = self.run_bootstrap(self.complete + [option, "https://raw.githubusercontent.com/matthewxmurphy/AIetherPanel-Strap/main", "--stage-two-sha256", sha])
                self.assert_rejected_before_prep(result)
                self.assertIn("immutable commit", result.stderr)
        result = self.run_bootstrap(self.complete + ["--install-source-root=https://mirror.example/source"])
        self.assert_rejected_before_prep(result)

    def test_unknown_installer_graph_and_malformed_hashes_are_rejected(self):
        for sha in ("0" * 64, "xyz", "", "$(touch /tmp/not-executed)"):
            with self.subTest(sha=sha):
                result = self.run_bootstrap(self.complete + ["--stage-two-sha256", sha])
                self.assert_rejected_before_prep(result)

    def test_unsafe_source_urls_and_controller_path_are_rejected(self):
        sha = digest((REPO / INSTALLER).read_bytes())
        for source in ("http://mirror.example/source", "https://user:password@mirror.example/source", "https://mirror.example/source?ref=main", "https://mirror.example/source#fragment", "https://mirror.example/source'bad", "https://mirror.example/a/../source", "https://mirror.example/a/./source"):
            with self.subTest(source=source):
                result = self.run_bootstrap(self.complete + ["--stage-two-source-root", source, "--stage-two-sha256", sha])
                self.assert_rejected_before_prep(result)
        result = self.run_bootstrap(self.complete, {"AETHERPANEL_CONTROLLER_BUNDLE_TAG": "../../escape"})
        self.assert_rejected_before_prep(result)

    def test_complete_pinned_assets_reach_only_stub_runner_once_then_cleanup(self):
        result = self.run_bootstrap(self.complete + ["--profile", "hybrid", "--node-name", "offline fixture"])
        self.assertEqual(result.returncode, 0, result.stderr)
        runners = self.records("runner.jsonl")
        self.assertEqual(len(runners), 1)
        record = runners[0]
        self.assertEqual(record["source_root"], PINNED)
        self.assertEqual(record["bundle_tag"], "controller-ready-stable-livewire")
        expected = {relative: digest((self.fixtures / relative).read_bytes()) for relative in (*KNOWN_FILES, SERVICE, BUNDLE)}
        self.assertEqual(record["files"], expected)
        self.assertIn("offline fixture", record["argv"])
        self.assertTrue(record["argv"][0].endswith("/install/aetherpanel-install.sh"))
        self.assertFalse(Path(record["temporary_root"]).exists())
        self.assertEqual(len(self.records("requests.jsonl")), 10)
        self.assertEqual(len((self.root / "prep.txt").read_text().splitlines()), 7)

    def test_custom_https_mirror_with_explicit_complete_trusted_hashes_is_supported(self):
        source = "https://mirror.example/private/source"
        sha = digest((REPO / INSTALLER).read_bytes()).upper()
        result = self.run_bootstrap(self.complete + ["--install-source-root", source, "--stage-two-sha256", sha], {"FAKE_SOURCE_ROOT": source})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.records("runner.jsonl")[0]["source_root"], source)
        self.assertTrue(all(source in " ".join(request) for request in self.records("requests.jsonl")))

    def test_every_script_and_support_file_tamper_is_rejected_before_prep(self):
        for relative in (*KNOWN_FILES, SERVICE, BUNDLE):
            with self.subTest(relative=relative):
                original = (self.fixtures / relative).read_bytes()
                (self.fixtures / relative).write_bytes(original + b"\nTAMPER\n")
                result = self.run_bootstrap(self.complete)
                self.assert_rejected_before_prep(result)
                self.assertIn("SHA256 mismatch", result.stderr)
                (self.fixtures / relative).write_bytes(original)

    def test_truncated_script_and_peer_manifest_cannot_supply_trust(self):
        for replacement in (b"#!/bin/bash\n", b'{"sha256":"peer-provided-digest","version":"latest"}'):
            with self.subTest(replacement=replacement):
                (self.fixtures / INSTALLER).write_bytes(replacement)
                result = self.run_bootstrap(self.complete)
                self.assert_rejected_before_prep(result)
                self.assertIn("SHA256 mismatch", result.stderr)
        self.assertTrue(all("manifest" not in " ".join(request) for request in self.records("requests.jsonl")))

    def test_missing_payload_and_network_failure_never_reach_prep(self):
        for relative in (INSTALLER, SERVICE, BUNDLE):
            with self.subTest(relative=relative):
                result = self.run_bootstrap(self.complete, {"FAIL_DOWNLOAD": relative})
                self.assert_rejected_before_prep(result)
                self.assertIn("download failed", result.stderr)

    def test_wrong_immutable_ref_or_missing_relative_path_fails_closed(self):
        sha = digest((REPO / INSTALLER).read_bytes())
        result = self.run_bootstrap(self.complete + ["--stage-two-source-root", PINNED.replace("25a19882d204dfba392090f84d563d8df9d4038c", "0" * 40), "--stage-two-sha256", sha])
        self.assert_rejected_before_prep(result)
        (self.fixtures / INSTALLER).unlink()
        result = self.run_bootstrap(self.complete)
        self.assert_rejected_before_prep(result)

    def test_runner_failure_preserves_status_and_removes_staged_files(self):
        result = self.run_bootstrap(self.complete, {"RUNNER_EXIT": "43"})
        self.assertEqual(result.returncode, 43, result.stderr)
        runners = self.records("runner.jsonl")
        self.assertEqual(len(runners), 1)
        self.assertFalse(Path(runners[0]["temporary_root"]).exists())


if __name__ == "__main__":
    unittest.main()
