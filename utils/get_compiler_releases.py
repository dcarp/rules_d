import argparse
from collections import namedtuple
from datetime import datetime, UTC
from hashlib import sha256
from itertools import groupby
from pathlib import Path
import re
from typing import Optional
from urllib.parse import urlsplit, urljoin

from github import Auth, Github, GitReleaseAsset
import requests

GITHUB_LDC_REPO = "ldc-developers/ldc"
ARCHIVE_TYPES = [".tar.xz", ".zip"]  # in order of the preference
OSES = ["linux", "osx", "windows"]
ARCHS = ["aarch64", "amd64", "arm64", "x86_64"]
DMD_REPO_URL = "https://downloads.dlang.org/releases/"
LOOKBACK_YEARS = 5


CompilerReleaseInfo = namedtuple(
    "CompilerRelease",
    ["compiler", "version", "os", "arch", "archive", "url", "file_name", "sha256"],
)


def canonical_arch(arch: str) -> str:
    if arch == "amd64":
        return "x86_64"
    elif arch == "arm64":
        return "aarch64"
    else:
        return arch


def remove_duplicates(releases: list[CompilerReleaseInfo]) -> list[CompilerReleaseInfo]:
    # remove release duplicates that differ on archive type only
    return list(
        next(v)
        for _, v in groupby(
            sorted(
                releases,
                key=lambda k: [
                    k.compiler,
                    k.version,
                    k.os,
                    k.arch,
                    ARCHIVE_TYPES.index(
                        k.archive
                    ),  # consider order in ARCHIVE_TYPES list
                ],
            ),
            key=lambda k: [k.compiler, k.version, k.os, k.arch],
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
        os=match.group(2),
        arch=canonical_arch("x86_64"),
        archive=match.group(3),
        url=urljoin(DMD_REPO_URL, url),
        file_name=file_name,
        sha256=None,
    )


def get_dmd_releases() -> list[CompilerReleaseInfo]:
    print("Getting DMD compiler releases...")
    response = requests.get(DMD_REPO_URL)
    response.raise_for_status()
    current_year = datetime.now().year
    years = [
        r
        for r in re.findall(r"<li><a href=\".*\">(\d*)</a></li>", response.text)
        if current_year - LOOKBACK_YEARS <= int(r) <= current_year
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


def get_ldc_repo(github_token: str):
    auth = Auth.Token(github_token)
    github = Github(auth=auth)
    return github.get_repo(GITHUB_LDC_REPO)


# match strings like ldc2-1.24.0-linux-aarch64.tar.xz
ldc_release_re = re.compile(
    f"ldc2-(.*)-({'|'.join(OSES)})-({'|'.join(ARCHS)})({'|'.join(re.escape(at) for at in ARCHIVE_TYPES)})"
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
        os=match.group(2),
        arch=canonical_arch(match.group(3)),
        archive=match.group(4),
        url=asset.browser_download_url,
        file_name=asset.name,
        sha256=None,
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
    print("Computing checksums")
    return [
        r._replace(sha256=sha256((cache_dir / r.file_name).read_bytes()).hexdigest())
        for r in releases
    ]


def generate_releases_bzl(releases: list[CompilerReleaseInfo], releases_bzl_file: Path):
    template = '''"""Known compiler list.

This file is generated with:
python3 utils/get_compiler_releases.py -c utils/cache --github-token <GITHUB_TOKEN> -o d/private/known_compiler_releases.bzl
"""

load(":common.bzl", "CompilerReleaseInfo")

known_compiler_releases = [
<PLACEHOLDER>
]
'''
    output = template.replace(
        "<PLACEHOLDER>",
        "\n".join(
            f'    CompilerReleaseInfo("{r.compiler}", "{r.version}", "{r.os}", "{r.arch}", "{r.url}", "{r.sha256}"),'
            for r in releases
        ),
    )
    releases_bzl_file.write_text(output)


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
        "-b",
        "--compiler_releases_bzl_file",
        type=Path,
        help="Known compiler releases .bzl file",
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

    compiler_releases = compute_sha256_digests(compiler_releases, cache_dir)

    if args.compiler_releases_bzl_file:
        generate_releases_bzl(compiler_releases, args.compiler_releases_bzl_file)


if __name__ == "__main__":
    main()
