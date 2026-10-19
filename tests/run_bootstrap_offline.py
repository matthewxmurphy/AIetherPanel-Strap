"""Reviewed offline fixture launcher; never runs an installer or host helper.

Maintained by Matthew X Murphy, https://MatthewxMurphy.com;
https://builtnotbegged.com. Existing project rights/distribution are unchanged.
Dependencies and the local Docker endpoint require separate review. No pulling,
daemon startup, privileged container, real HOME or host socket mount is allowed.
"""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import uuid

REPO = Path(__file__).resolve().parents[1]
EXPORTS = (
    "install/bootstrap.sh", "install/aetherpanel-install.sh",
    "install/steps/10-preflight.sh", "install/steps/20-packages.sh",
    "install/steps/30-tailscale.sh", "install/steps/40-panel-files.sh",
    "install/steps/50-services.sh", "conf/lighttpd-controller.conf.template",
    "ui/public/index.php", "tests/test_bootstrap_integrity.py",
)
QUALIFY = r'''
import hashlib, json, os, pathlib, re, shutil, subprocess, sys
assert os.getuid() != 0
bash = pathlib.Path('/bin/bash')
env = {key: os.environ[key] for key in ('PATH', 'HOME', 'TMPDIR', 'LANG')}
version = subprocess.check_output([str(bash), '--noprofile', '--norc', '--version'], env=env, text=True)
assert int(re.search(r'version (\d+)', version).group(1)) >= 4
tools = {}
for name in ('mktemp', 'mkdir', 'dirname', 'mv', 'rm', 'cat', 'sha256sum'):
    p = pathlib.Path(shutil.which(name)); tools[name] = {'path': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
print(json.dumps({'uid': os.getuid(), 'bash_version': version.splitlines()[0], 'bash_sha256': hashlib.sha256(bash.read_bytes()).hexdigest(), 'python_version': sys.version.split()[0], 'python_sha256': hashlib.sha256(pathlib.Path(sys.executable).read_bytes()).hexdigest(), 'tools': tools}))
'''
SENTINEL = "#!/bin/sh\nprintf '%s\\n' \"$0\" >>/owned/sentinel.log\nexit 125\n"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--docker", required=True)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--image", required=True, help="Reviewed cached immutable sha256 image ID")
    parser.add_argument("--evidence-dir", required=True, help="New private directory outside source")
    parser.add_argument("--qualify", action="store_true", help="Version/hash-only container; no source mount/tests")
    parser.add_argument("--qualification", help="Prior reviewed version/hash-only receipt")
    parser.add_argument("--tree", help="Expected frozen Git index tree; required for tests")
    parser.add_argument("--expect-tests", type=int, help="Required exact non-skipped method count for fixture mode")
    args = parser.parse_args()
    if not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
        raise SystemExit("Launch Python with -I -S -B")
    if os.getuid() == 0:
        raise SystemExit("Run as an unprivileged local operator")
    if not re.fullmatch(r"sha256:[a-f0-9]{64}", args.image):
        raise SystemExit("Exact immutable cached image ID required")
    docker = Path(args.docker).resolve(strict=True)
    if not docker.is_file() or not os.access(docker, os.X_OK) or docker.stat().st_mode & 0o022:
        raise SystemExit("Unsafe Docker executable")
    if not args.socket.startswith("unix:///"):
        raise SystemExit("Explicit reviewed local Unix Docker socket required")
    socket_path = Path(args.socket.removeprefix("unix://"))
    socket_stat = socket_path.stat()
    if not stat.S_ISSOCK(socket_stat.st_mode) or socket_stat.st_uid != os.getuid():
        raise SystemExit("Expected the reviewed user-owned Unix socket")
    socket_metadata = {"path": str(socket_path), "resolved": str(socket_path.resolve()),
                       "uid": socket_stat.st_uid, "gid": socket_stat.st_gid,
                       "mode": oct(stat.S_IMODE(socket_stat.st_mode))}
    evidence = Path(args.evidence_dir).absolute()
    if evidence == REPO or REPO in evidence.parents:
        raise SystemExit("Evidence must stay outside source")
    evidence.mkdir(mode=0o700)  # No reuse/chmod of caller state.
    with tempfile.TemporaryDirectory(prefix="strap-offline-owned-", dir=evidence) as td:
        task = Path(td)
        runtime = task / "owned"; runtime.mkdir(mode=0o700)
        for name in ("home", "tmp", "sentinels"):
            (runtime / name).mkdir(mode=0o700)
        (task / "docker").mkdir(mode=0o700)
        client_env = {"PATH": "/usr/bin:/bin", "HOME": str(runtime / "home"),
                      "TMPDIR": str(runtime / "tmp"), "LANG": "C.UTF-8",
                      "DOCKER_CONFIG": str(task / "docker")}
        docker_base = [str(docker), "--host", args.socket]

        def command(arguments, **kwargs):
            return subprocess.run(docker_base + arguments, env=client_env, text=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  timeout=kwargs.pop("timeout", 30), **kwargs)

        inspected = command(["image", "inspect", args.image], check=True)
        image = json.loads(inspected.stdout)[0]
        if image["Id"] != args.image or image["Os"] != "linux":
            raise SystemExit("Cached image identity/platform mismatch")
        if image["Config"].get("Volumes"):
            raise SystemExit("Unreviewed anonymous image volumes")
        safe_image_keys = {"PATH", "LANG", "GPG_KEY", "PYTHON_VERSION", "PYTHON_SHA256"}
        if any(item.split("=", 1)[0] not in safe_image_keys for item in image["Config"].get("Env", [])):
            raise SystemExit("Unreviewed image startup environment")
        export_manifest = {}
        mounts = []
        qualification = None
        expected_names = []
        if not args.qualify:
            if not args.tree or not args.qualification or not args.expect_tests or args.expect_tests < 1:
                raise SystemExit("Reviewed tree, qualification and positive expected test count required")
            qualification = json.loads(Path(args.qualification).read_text())
            if qualification["image_id"] != args.image or not qualification["container_gone"]:
                raise SystemExit("Qualification does not bind this image/cleanup")
            qualified = qualification["metadata"]
            if not re.fullmatch(r"[a-f0-9]{64}", qualified["bash_sha256"]):
                raise SystemExit("Missing qualified Bash digest")
            git = ["/usr/bin/git", "-C", str(REPO)]
            tree = subprocess.check_output(git + ["write-tree"], env=client_env, text=True).strip()
            if tree != args.tree:
                raise SystemExit("Git index differs from the frozen review")
            source = task / "source"; source.mkdir(mode=0o700)
            for name in EXPORTS:
                data = subprocess.check_output(git + ["show", ":" + name], env=client_env)
                target = source / name; target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data); target.chmod(0o444)
                export_manifest[name] = digest(data)
            module = ast.parse((source / "tests/test_bootstrap_integrity.py").read_text())
            expected_names = sorted(node.name for cls in module.body if isinstance(cls, ast.ClassDef)
                                    for node in cls.body if isinstance(node, ast.FunctionDef) and node.name.startswith("test_"))
            if len(expected_names) != args.expect_tests:
                raise SystemExit("Frozen source test inventory differs from required count")
            mounts = ["--mount", f"type=bind,src={source},dst=/source,readonly"]
        for name in ("apt-get", "systemctl", "useradd", "usermod", "tailscale", "sudo",
                     "ssh", "curl", "wget", "service", "reboot", "shutdown", "chown",
                     "chmod", "install", "touch"):
            target = runtime / "sentinels" / name; target.write_text(SENTINEL); target.chmod(0o700)
        owner = uuid.uuid4().hex
        name = "strap-offline-" + owner
        container_env = ["PATH=/owned/sentinels:/usr/local/bin:/usr/bin:/bin", "HOME=/owned/home",
                         "TMPDIR=/owned/tmp", "LANG=C.UTF-8"]
        if args.qualify:
            payload = ["/usr/local/bin/python3", "-I", "-S", "-B", "-c", QUALIFY]
        else:
            container_env += ["BOOTSTRAP_TEST_BASH=/bin/bash",
                              "BOOTSTRAP_TEST_BASH_SHA256=" + qualification["metadata"]["bash_sha256"]]
            payload = ["/usr/local/bin/python3", "-I", "-S", "-B", "-m", "unittest",
                       "discover", "-s", "/source/tests", "-p", "test_bootstrap_integrity.py", "-v"]
        cidfile = task / "container.cid"
        run_args = ["run", "--pull=never", "--rm", "--name", name, "--cidfile", str(cidfile),
                    "--label", "io.builtnotbegged.fixture=" + owner,
                    "--network=none", "--ipc=private", "--read-only", "--cap-drop=ALL",
                    "--security-opt=no-new-privileges", "--pids-limit=64", "--memory=256m", "--cpus=1",
                    "--user", f"{os.getuid()}:{os.getgid()}", "--workdir", "/owned",
                    "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,mode=1777",
                    "--mount", f"type=bind,src={runtime},dst=/owned",
                    *mounts, "--entrypoint", "/usr/bin/env", args.image, "-i", *container_env, *payload]
        receipt = {"image_id": args.image, "image_repo_digests": image.get("RepoDigests"),
                   "image_config": {key: image["Config"].get(key) for key in ("Env", "Entrypoint", "Cmd", "User", "Volumes", "WorkingDir")},
                   "docker_sha256": digest(docker.read_bytes()), "source_tree": args.tree,
                   "host_python_path": str(Path(sys.executable).resolve()),
                   "host_python_sha256": digest(Path(sys.executable).read_bytes()),
                   "socket": socket_metadata,
                   "source_exports": export_manifest, "sentinel_sha256": digest(SENTINEL.encode()),
                   "launcher_sha256": digest(Path(__file__).read_bytes()), "qualification_only": args.qualify,
                   "container_name": name, "command": docker_base + run_args}
        result = None
        try:
            result = command(run_args, timeout=180)
            (evidence / "stdout.log").write_text(result.stdout)
            (evidence / "stderr.log").write_text(result.stderr)
            receipt["exit"] = result.returncode
            if args.qualify and result.returncode == 0:
                receipt["metadata"] = json.loads(result.stdout)
            elif not args.qualify:
                observed = sorted(re.findall(r"^(test_[A-Za-z0-9_]+) \(.*\) \.\.\. ok$", result.stderr, re.M))
                count = re.search(r"^Ran (\d+) tests? in ", result.stderr, re.M)
                receipt["expected_test_names"] = expected_names
                receipt["passed_test_names"] = observed
                receipt["fixture_accepted"] = (result.returncode == 0 and observed == expected_names
                    and count is not None and int(count.group(1)) == args.expect_tests
                    and re.search(r"^OK$", result.stderr, re.M) is not None
                    and "skipped" not in result.stderr.lower())
        finally:
            receipt["container_gone"] = False
            try:
                cid = cidfile.read_text().strip() if cidfile.exists() else None
                if cid and not re.fullmatch(r"[a-f0-9]{64}", cid):
                    raise RuntimeError("Malformed owned cidfile")
                remaining = command(["container", "inspect", cid or name])
                if remaining.returncode == 0:
                    state = json.loads(remaining.stdout)[0]
                    if state["Name"] != "/" + name or state["Config"]["Labels"].get("io.builtnotbegged.fixture") != owner:
                        raise RuntimeError("Refusing cleanup of an unowned container")
                    if not re.fullmatch(r"[a-f0-9]{64}", state["Id"]) or (cid and state["Id"] != cid):
                        raise RuntimeError("Owned container ID mismatch")
                    cid = state["Id"]
                    command(["rm", "--force", cid], check=True)
                receipt["container_id"] = cid
                confirmation = command(["container", "inspect", cid or name])
                receipt["container_gone"] = confirmation.returncode != 0 and "no such container" in confirmation.stderr.lower()
                if not receipt["container_gone"]:
                    raise RuntimeError("Owned container absence could not be confirmed")
            except Exception as error:
                receipt["cleanup_error"] = str(error)
            finally:
                sentinel = runtime / "sentinel.log"
                receipt["unexpected_host_command_attempts"] = sentinel.read_text().splitlines() if sentinel.exists() else []
                (evidence / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        if not receipt["container_gone"] or receipt["unexpected_host_command_attempts"]:
            raise SystemExit("Owned cleanup or denied-command assertion failed")
        if result is None or result.returncode:
            raise SystemExit(result.returncode if result else 1)
        if not args.qualify and not receipt.get("fixture_accepted"):
            raise SystemExit("Exact expected test inventory did not pass without skips")
        print(json.dumps({"receipt": str(evidence / "receipt.json"), "qualify_only": args.qualify, "exit": 0}))


if __name__ == "__main__":
    main()
