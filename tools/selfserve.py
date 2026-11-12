#!/usr/bin/env python3
"""Verify a committed source archive, then produce a local self-serve pack.

Recipe commands are trusted maintainer code. No network publication, repository
visibility change, Git mutation, or contact messaging is implemented here.
"""
import argparse
import datetime as dt
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import signal
import shlex
import shutil
import subprocess
import tarfile
import tempfile


def test_counts(text):
    matches = re.findall(r"Build Summary:.*?;(\s*\d+)/(\d+) tests passed(?: \((\d+) skipped\))?", text)
    if not matches:
        return None
    passed, total, skipped = matches[-1]
    return {"passed": int(passed), "total": int(total), "skipped": int(skipped or 0)}


def execute(command, cwd, timeout, env):
    with tempfile.TemporaryFile() as output:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        timed_out = False
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        output.seek(0)
        return process.returncode, timed_out, output.read().decode(errors="replace")


def verify(recipe, repo, destination):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", recipe["project"]):
        raise ValueError("project must be a safe artifact name")
    if recipe["visibility"] not in {"private", "public"} or not recipe.get("steps"):
        raise ValueError("declare public/private visibility and at least one acceptance step")
    repo, destination = Path(repo).resolve(), Path(destination).resolve()
    if destination == repo or repo in destination.parents:
        raise ValueError("the output directory must be outside the source repository")
    destination.mkdir(parents=True, exist_ok=False)
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    source = subprocess.check_output(["git", "archive", "--format=tar", commit], cwd=repo)
    recipe_sha = hashlib.sha256(json.dumps(recipe, sort_keys=True).encode()).hexdigest()
    result = {"schema": 1, "project": recipe["project"], "commit": commit,
              "visibility": recipe["visibility"], "recipe_sha256": recipe_sha,
              "measured_at": dt.datetime.now(dt.timezone.utc).isoformat(),
              "platform": {"system": platform.system(), "machine": platform.machine()},
              "status": "FAIL", "steps": [], "limitations": recipe.get("limitations", [])}
    (destination / "recipe.json").write_text(json.dumps(recipe, indent=2) + "\n")
    archive = destination / (recipe["project"] + "-source.tar.gz")
    archive.write_bytes(gzip.compress(source, mtime=0))
    try:
        with tempfile.TemporaryDirectory(prefix="flight-source-") as workspace:
            root = Path(workspace).resolve()
            with tarfile.open(fileobj=io.BytesIO(source)) as bundle:
                # Python 3.12+: reject absolute paths, traversal and unsafe links.
                bundle.extractall(root, filter="data")
            for required in recipe.get("required_files", ["README.md", "LICENSE"]):
                if not (root / required).is_file():
                    raise ValueError("required shipped file missing: " + required)
            if recipe.get("systems") and platform.system() not in recipe["systems"]:
                raise ValueError("this runtime is outside the recipe's supported systems")
            env = os.environ.copy()
            # Commands may use an isolated synthetic-state path, never a real ledger.
            env.update({key: value.replace("{scratch}", str(root))
                        for key, value in recipe.get("environment", {}).items()})
            passed = True
            for number, step in enumerate(recipe["steps"]):
                argv = step["argv"]
                if not isinstance(argv, list) or not argv or not all(isinstance(x, str) for x in argv):
                    raise ValueError("commands must be nonempty argument arrays")
                code, timeout, log = execute(argv, root, step.get("timeout_seconds", 180), env)
                counts = test_counts(log) if "minimum_tests" in step else None
                ok = code == step.get("expected_exit", 0) and not timeout
                if "minimum_tests" in step:
                    ok = ok and counts is not None and counts["passed"] >= step["minimum_tests"]
                if step.get("contains"):
                    ok = ok and step["contains"] in log
                name = f"step-{number:02}.log"
                (destination / name).write_text(log.replace(str(root), "{source}"))
                result["steps"].append({"name": step["name"], "argv": argv,
                                        "exit": code, "timeout": timeout,
                                        "tests": counts, "passed": bool(ok), "log": name})
                if not ok:
                    passed = False
                    break
            result["status"] = "PASS" if passed else "FAIL"
            if passed:
                for relative in recipe.get("bundle_paths", []):
                    item = (root / relative).resolve()
                    if not item.is_relative_to(root) or not item.is_file():
                        raise ValueError("bundle path must be a shipped build output: " + relative)
                    target = destination / "bin" / item.name
                    target.parent.mkdir(exist_ok=True)
                    shutil.copy2(item, target)
    except (ValueError, OSError, subprocess.SubprocessError, tarfile.TarError) as error:
        result["status"] = "FAIL"
        result["error"] = str(error)
    (destination / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    (destination / "TRY.md").write_text(
        f"# {recipe['project']}\n\n{recipe['task']}\n\n"
        f"Source commit: `{commit}`. Package visibility: **{recipe['visibility']}**.\n\n"
        "Extract the source archive into an empty directory. Use Zig 0.16.0 and run:\n\n```sh\n"
        + "\n".join(shlex.join(s["argv"]) for s in recipe["steps"])
        + "\n```\n\nRead result.json before using this pack. FAIL means the acceptance task did not pass.\n"
        + "\n".join("- " + text for text in recipe.get("limitations", [])) + "\n")
    files = sorted(path for path in destination.rglob("*") if path.is_file())
    (destination / "SHA256SUMS").write_text("".join(
        hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.relative_to(destination).as_posix() + "\n" for path in files))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recipe", type=Path)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = verify(json.loads(args.recipe.read_text()), args.repo, args.out)
    print(json.dumps({key: result[key] for key in ("project", "commit", "status")}, indent=2))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
