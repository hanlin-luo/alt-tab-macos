#!/usr/bin/env python3
"""push-via-api.py — Replicate unpushed local commits to the GitHub fork via the
Git Data API. Fallback for when direct `git push` fails (e.g. local proxy returns
502 for github.com git endpoints while api.github.com stays reachable via gh).

Creates blobs, trees and commits with byte-identical content, timestamps and
messages, so the resulting SHAs match local commits exactly, then fast-forwards
the remote branch. Aborts WITHOUT touching the remote ref if any SHA mismatches,
so local and remote can never diverge silently.

Usage:  python3 push-via-api.py [branch]        (default branch: master)
"""
import base64
import json
import subprocess
import sys

REPO = "hanlin-luo/alt-tab-macos"
BRANCH = sys.argv[1] if len(sys.argv) > 1 else "master"
WORK = "/Users/lmc/codes/tools/alt-tab-macos"


def gh_api(method, endpoint, payload=None):
    cmd = ["gh", "api", "-X", method, f"/repos/{REPO}{endpoint}"]
    data = None
    if payload is not None:
        cmd += ["--input", "-"]
        data = json.dumps(payload).encode()
    r = subprocess.run(cmd, input=data, capture_output=True)
    if r.returncode != 0:
        print(f"API ERROR {method} {endpoint}:\n{r.stderr.decode()}", file=sys.stderr)
        sys.exit(1)
    return json.loads(r.stdout.decode())


def git(*args):
    r = subprocess.run(["git", *args], cwd=WORK, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"git error on {args}:\n{r.stderr}", file=sys.stderr)
        sys.exit(1)
    return r.stdout.strip()


def main():
    remote_head = gh_api("GET", f"/git/ref/heads/{BRANCH}")["object"]["sha"]
    print(f"remote {BRANCH}: {remote_head[:12]}")

    revs = git("rev-list", "--reverse", f"{remote_head}..{BRANCH}")
    revs = revs.splitlines() if revs else []
    if not revs:
        print("nothing to push — remote already up to date")
        return
    print(f"{len(revs)} local commit(s) to replicate")

    for sha in revs:
        parent = git("log", "-1", "--format=%P", sha).split()[0]
        an = git("log", "-1", "--format=%an", sha)
        ae = git("log", "-1", "--format=%ae", sha)
        ad = git("log", "-1", "--format=%aI", sha)
        cd = git("log", "-1", "--format=%cI", sha)
        message = git("log", "-1", "--format=%B", sha).rstrip("\n") + "\n"

        # Tree entries changed by this commit (diff vs first parent)
        entries = []
        for line in git("diff-tree", "--no-commit-id", "-r", sha).splitlines():
            meta, path = line.split("\t", 1)
            _old_mode, new_mode, _old_sha, new_sha, status = meta.split()
            if status.startswith("D"):
                entries.append({"path": path, "mode": _old_mode, "type": "blob", "sha": None})
                print(f"  delete {path}")
                continue
            content = subprocess.run(
                ["git", "cat-file", "blob", new_sha], cwd=WORK,
                capture_output=True, check=True).stdout
            resp = gh_api("POST", "/git/blobs", {
                "content": base64.b64encode(content).decode(), "encoding": "base64"})
            if resp["sha"] != new_sha:
                sys.exit(f"blob mismatch for {path}: {resp['sha']} != {new_sha} — ref untouched")
            print(f"  blob {path}: {new_sha[:12]} OK")
            entries.append({"path": path, "mode": new_mode, "type": "blob", "sha": new_sha})

        tree = gh_api("POST", "/git/trees", {
            "base_tree": git("rev-parse", f"{parent}^{{tree}}"),
            "tree": entries,
        })["sha"]
        expected_tree = git("rev-parse", f"{sha}^{{tree}}")
        if tree != expected_tree:
            sys.exit(f"tree mismatch: {tree} != {expected_tree} — ref untouched")
        print(f"  tree: {tree[:12]} OK")

        commit = gh_api("POST", "/git/commits", {
            "message": message,
            "tree": tree,
            "parents": [parent],
            "author": {"name": an, "email": ae, "date": ad},
            "committer": {"name": an, "email": ae, "date": cd},
        })["sha"]
        if commit != sha:
            sys.exit(f"commit mismatch: {commit} != {sha} — ref untouched")
        print(f"  commit: {commit[:12]} OK")

    gh_api("PATCH", f"/git/refs/heads/{BRANCH}", {"sha": revs[-1], "force": False})
    print(f"\nSUCCESS: remote {BRANCH} -> {revs[-1][:12]}")
    print(f"https://github.com/{REPO}")


if __name__ == "__main__":
    main()
