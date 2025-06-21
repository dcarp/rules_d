#!/usr/bin/env python3

import argparse
from base64 import b64encode
from collections import namedtuple
from datetime import datetime, UTC
from hashlib import sha256, sha384
from itertools import groupby
from json import dumps
from pathlib import Path
import re
from typing import Optional
from urllib.parse import urlsplit, urljoin

from github import Auth, Github, GitReleaseAsset
import requests

GITHUB_LDC_REPO = "ldc-developers/ldc"
ARCHIVE_TYPES = [".tar.xz", ".zip"]  # in order of the preference
OSES = ["linux", "osx", "windows"]
CPUS = ["aarch64", "amd64", "arm64", "x86_64"]
DMD_REPO_URL = "https://downloads.dlang.org/releases/"
DMD_CHANGELOG_URL = "https://dlang.org/changelog/index.html"
LOOKBACK_YEARS = 5


CompilerReleaseInfo = namedtuple(
    "CompilerRelease",
    [
        "compiler",
        "version",
        "os",
        "cpu",
        "archive",
        "url",
        "file_name",
        "sha256",
        "integrity",
    ],
)


def canonical_cpu(cpu: str) -> str:
    if cpu == "amd64":
        return "x86_64"
    elif cpu == "arm64":
        return "aarch64"
    else:
        return cpu


def canonical_os(os: str) -> str:
    if os == "osx":
        return "macos"
    else:
        return os


def semver_to_tuple(version: str) -> tuple[int, int, int]:
    return tuple(int(part) for part in version.split(".")[:3])


def remove_duplicates(releases: list[CompilerReleaseInfo]) -> list[CompilerReleaseInfo]:
    # remove release duplicates that differ on archive type only
    return list(
        next(v)
        for _, v in groupby(
            sorted(
                releases,
                key=lambda r: [
                    r.compiler,
                    semver_to_tuple(r.version),
                    r.os,
                    r.cpu,
                    ARCHIVE_TYPES.index(
                        r.archive
                    ),  # consider order in ARCHIVE_TYPES list
                ],
            ),
            key=lambda r: [r.compiler, r.version, r.os, r.cpu],
        )
    )


# match strings like dmd.2.095.1.linux.tar.xz
dmd_release_re = re.compile(
    f"dmd[.](.*)[.]({'|'.join(OSES)})({'|'.join(re.escape(at) for at in ARCHIVE_TYPES)})"
)


def get_dmd_compiler_release_info(url: str) -> Optional[CompilerReleaseInfo]:
    u = urlsplit(url)
    file_name = Path(u.path).name
    match = dmd_release_re.fullmatch(file_name)
    if not match:
        return None
    return CompilerReleaseInfo(
        compiler="dmd",
        version=match.group(1),
        os=canonical_os(match.group(2)),
        cpu=canonical_cpu("x86_64"),
        archive=match.group(3),
        url=urljoin(DMD_REPO_URL, url),
        file_name=file_name,
        sha256=None,
        integrity=None,
    )


def get_dmd_releases_from_releases_url() -> list[CompilerReleaseInfo]:
    # This doesn't work for the moment as the official DMD releases page does not contain all releases.
    response = requests.get(DMD_REPO_URL)
    response.raise_for_status()
    cuttoff_year = datetime.now().year - LOOKBACK_YEARS
    years = [
        r
        for r in re.findall(r"<li><a href=\".*\">(\d*)</a></li>", response.text)
        if cuttoff_year <= int(r)
    ]
    compiler_releases = []
    for year in years:
        response = requests.get(DMD_REPO_URL + year)
        response.raise_for_status()
        urls = re.findall(r"<li><a href=\"(.*)\">.*</a></li>", response.text)
        compiler_releases.extend(
            info
            for info in (get_dmd_compiler_release_info(url) for url in urls)
            if info
        )
    return remove_duplicates(compiler_releases)


def get_dmd_releases_from_changelog() -> list[CompilerReleaseInfo]:
    response = requests.get(DMD_CHANGELOG_URL)
    response.raise_for_status()
    compiler_versions = []
    cutoff_year = datetime.now().year - LOOKBACK_YEARS
    compiler_versions = set(
        match.group(1)
        for match in re.finditer(
            r"<li><a id=\"(.*)\" href=.*[(](\w{3} \d{1,2}, \d{4})[)]</span></li>",
            response.text,
        )
        if cutoff_year <= int(match.group(2)[-4:])
    )
    compiler_releases = []
    for version in compiler_versions:
        response = requests.get(DMD_REPO_URL + "2.x/" + version)
        if response.status_code == 404:
            print(f"DMD version {version} not found, skipping...")
            continue
        response.raise_for_status()
        urls = re.findall(r"<li><a href=\"(.*)\">.*</a></li>", response.text)
        compiler_releases.extend(
            info
            for info in (get_dmd_compiler_release_info(url) for url in urls)
            if info
        )
    return remove_duplicates(compiler_releases)


def get_dmd_releases() -> list[CompilerReleaseInfo]:
    print("Getting DMD compiler releases...")
    compiler_releases = get_dmd_releases_from_changelog()
    return remove_duplicates(compiler_releases)


def get_ldc_repo(github_token: str):
    auth = Auth.Token(github_token)
    github = Github(auth=auth)
    return github.get_repo(GITHUB_LDC_REPO)


# match strings like ldc2-1.24.0-linux-aarch64.tar.xz
ldc_release_re = re.compile(
    f"ldc2-(.*)-({'|'.join(OSES)})-({'|'.join(CPUS)})({'|'.join(re.escape(at) for at in ARCHIVE_TYPES)})"
)


def get_ldc_compiler_release_info(
    asset: GitReleaseAsset,
) -> Optional[CompilerReleaseInfo]:
    match = ldc_release_re.fullmatch(asset.name)
    if not match:
        return None
    return CompilerReleaseInfo(
        compiler="ldc",
        version=match.group(1),
        os=canonical_os(match.group(2)),
        cpu=canonical_cpu(match.group(3)),
        archive=match.group(4),
        url=asset.browser_download_url,
        file_name=asset.name,
        sha256=None,
        integrity=None,
    )


def get_ldc_releases(github_token: str) -> list[CompilerReleaseInfo]:
    print("Getting LDC compiler releases...")
    cutoff_date = datetime(datetime.now().year - LOOKBACK_YEARS, 1, 1, tzinfo=UTC)
    compiler_releases = []
    for release in get_ldc_repo(github_token).get_releases():
        if release.prerelease or release.published_at < cutoff_date:
            continue
        compiler_releases.extend(
            info
            for info in (get_ldc_compiler_release_info(a) for a in release.get_assets())
            if info
        )
    return remove_duplicates(compiler_releases)


def download_release(
    release: CompilerReleaseInfo, cache_dir: Path, auth_token: str = ""
):
    asset_file = cache_dir / release.file_name
    if asset_file.exists():
        print(f"{release.file_name} is already downloaded.")
        return
    print(f"Downloading from {release.url}...")

    response = requests.get(
        release.url,
        headers={"Authorization": f"token {auth_token}"} if auth_token else None,
        stream=True,
    )
    response.raise_for_status()

    with open(asset_file, "wb") as f:
        for chunk in response.iter_content(chunk_size=1024 * 1024):
            f.write(chunk)

    print(f"Downloaded {release.file_name} to {asset_file}.")


def compute_sha256_digests(
    releases: list[CompilerReleaseInfo], cache_dir: Path
) -> list[CompilerReleaseInfo]:
    print("Computing sha256 digests")
    return [
        r._replace(sha256=sha256((cache_dir / r.file_name).read_bytes()).hexdigest())
        for r in releases
    ]


def compute_integrity_metadata(
    releases: list[CompilerReleaseInfo], cache_dir: Path
) -> list[CompilerReleaseInfo]:
    print("Computing integrity metadata")
    return [
        r._replace(
            integrity="sha384-{}".format(
                b64encode(
                    sha384((cache_dir / r.file_name).read_bytes()).digest()
                ).decode()
            )
        )
        for r in releases
    ]


def platform_id(os: str, cpu: str) -> str:
    if os == "linux":
        return f"{cpu}-unknown-linux-gnu"
    elif os == "macos":
        return f"{cpu}-apple-darwin"
    elif os == "windows":
        return f"{cpu}-pc-windows-msvc"
    else:
        return "unknown"


def group_by_compiler_version(
    releases: list[CompilerReleaseInfo],
) -> dict[str, CompilerReleaseInfo]:
    return {
        f"{k[0]}-{k[1]}": {
            platform_id(p.os, p.cpu): {"url": p.url, "integrity": p.integrity}
            for p in v
        }
        for k, v in groupby(
            sorted(releases, key=lambda r: [r.compiler, semver_to_tuple(r.version)]),
            key=lambda r: [r.compiler, r.version],
        )
    }


def generate_versions_bzl(releases: list[CompilerReleaseInfo], versions_bzl_file: Path):
    header = '''"""Mirror of D compiler release information.

This file is generated with:
python3 d/private/sdk/versions_generator/generate_versions_bzl.py -c ~/.cache/d_releases --github-token <GITHUB_TOKEN> -o d/private/sdk/versions.bzl
"""

SDK_VERSIONS = '''

    versions_bzl_file.write_text(
        header
        + dumps(group_by_compiler_version(releases), indent=4)
        .replace('"\n', '",\n')
        .replace(" }\n", " },\n")
        + "\n"
    )


def main():
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument("-c", "--cache", type=Path, help="Cache directory")
    arg_parser.add_argument(
        "--skip-dmd", action="store_true", help="Skip DMD compilers"
    )
    arg_parser.add_argument(
        "--skip-ldc", action="store_true", help="Skip LDC compilers"
    )
    arg_parser.add_argument(
        "-n",
        "--no-refresh",
        action="store_true",
        help="Don't check upstream. Use local cache-only",
    )
    arg_parser.add_argument("--github-token", type=str, help="GitHub token")
    arg_parser.add_argument(
        "-o",
        "--sdk_versions_bzl_file",
        type=Path,
        help="Known compiler version .bzl file",
    )
    args = arg_parser.parse_args()
    cache_dir = args.cache
    if not cache_dir.exists() or not cache_dir.is_dir():
        arg_parser.error(f"cache parameter '{cache_dir}' is not a directory")
    if not args.skip_ldc and not args.github_token:
        arg_parser.error("No GitHub token specified")

    compiler_releases = []

    if not args.skip_dmd:
        compiler_releases.extend(get_dmd_releases())
    if not args.skip_ldc:
        compiler_releases.extend(get_ldc_releases(args.github_token))

    for release in compiler_releases:
        auth_token = args.github_token if release.compiler == "ldc" else None
        assert auth_token or release.compiler != "ldc", "Empty GitHub token"
        download_release(release, cache_dir, auth_token)

    compiler_releases = compute_integrity_metadata(compiler_releases, cache_dir)

    if args.sdk_versions_bzl_file:
        generate_versions_bzl(compiler_releases, args.sdk_versions_bzl_file)


if __name__ == "__main__":
    main()
