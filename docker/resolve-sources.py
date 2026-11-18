#!/usr/bin/env python3
"""Resolve source releases once per build; emit a Docker Bake JSON override.

Usage: docker buildx bake --print | python3 docker/resolve-sources.py > sources.json
No PHP or FrankenPHP image registry is queried. GH_TOKEN is used only for the
GitHub API, never sent to source download endpoints.
"""
import json
import os
import re
import sys
import urllib.request


def fetch(url):
    headers = {"User-Agent": "prvious-frankenphp-source-builder"}
    if url.startswith("https://api.github.com/") and os.environ.get("GH_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=120) as response:
        return response.read()


def resolve(metadata, download=fetch):
    targets = {name: target for name, target in metadata["target"].items()
               if name.startswith("runner-")}
    if not targets:
        raise ValueError("No runner targets in Bake metadata")
    releases = {}
    for target in targets.values():
        minor = target["args"]["VERSION"].split("-")[0]
        if not re.fullmatch(r"8\.[45]", minor):
            raise ValueError(f"Unsupported PHP minor: {minor}")
        if minor in releases:
            continue
        release = json.loads(download(f"https://www.php.net/releases/?json&version={minor}"))
        version = release["version"]
        if not re.fullmatch(re.escape(minor) + r"\.\d+", version):
            raise ValueError(f"Unexpected PHP release: {version}")
        source = next(s for s in release["source"] if s["filename"] == f"php-{version}.tar.xz")
        checksum = source["sha256"]
        if not re.fullmatch(r"[a-f0-9]{64}", checksum):
            raise ValueError("Invalid PHP SHA256")
        releases[minor] = {"PHP_VERSION": version, "PHP_SHA256": checksum}
    release = json.loads(download("https://api.github.com/repos/php/frankenphp/releases/latest"))
    version = release["tag_name"]
    if release.get("draft") or release.get("prerelease") or not re.fullmatch(r"v\d+\.\d+\.\d+", version):
        raise ValueError(f"Unexpected FrankenPHP release: {version}")
    commit = json.loads(download(f"https://api.github.com/repos/php/frankenphp/commits/{version}"))["sha"]
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("Invalid FrankenPHP commit")
    common = {"FRANKENPHP_VERSION": version, "FRANKENPHP_REVISION": commit}
    return {"target": {name: {"args": {**releases[target["args"]["VERSION"].split("-")[0]], **common}}
                       for name, target in targets.items()}}


if __name__ == "__main__":
    json.dump(resolve(json.load(sys.stdin)), sys.stdout, indent=4)
    print()
