import argparse
from datetime import datetime, timedelta, UTC
from hashlib import sha256
from pathlib import Path
import re

from github import Auth, Github
import requests

GITHUB_LDC_REPO = "ldc-developers/ldc"
ARCHIVE_FILES = [".tar.xz"]
DMD_REPO_URL = "https://downloads.dlang.org/releases/2.x/"

cutoff_date = datetime.now(UTC).replace(
    hour=0, minute=0, second=0, microsecond=0
) - timedelta(days=5 * 365)


def consider_asset(asset_name: str, ignore_arch=False) -> bool:
    return (
        any(asset_name.endswith(ext) for ext in ARCHIVE_FILES)
        and any(os in asset_name for os in ["linux", "osx"])
        and (
            ignore_arch
            or any(
                arch in asset_name for arch in ["aarch64", "arm64", "amd64", "x86_64"]
            )
        )
    )


def get_dmd_releases():
    response = requests.get(DMD_REPO_URL)
    response.raise_for_status()
    return [
        r
        for r in re.findall(r"<li><a href=\".*\">(.*)</a></li>", response.text)
        if r >= "2.084.0"
    ]


def download_dmd_release_assets(release, cache_dir: Path):
    response = requests.get(f"{DMD_REPO_URL}{release}/")
    response.raise_for_status()
    for asset in re.findall(r"<li><a href=\".*\">(.*)</a></li>", response.text):
        if not consider_asset(asset, ignore_arch=True):
            continue
        asset_file = cache_dir / asset
        if asset_file.exists():
            print(f"{asset} is already downloaded.")
            continue
        print(f"Downloading {asset}...")
        response = requests.get(
            f"{DMD_REPO_URL}{release}/{asset}",
            stream=True,
        )
        response.raise_for_status()

        with open(asset_file, "wb") as f:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                f.write(chunk)

        print(f"Downloaded {asset} to {asset_file}.")


def download_dmd_releases(cache_dir: Path):
    for release in get_dmd_releases():
        download_dmd_release_assets(release, cache_dir)


def get_ldc_repo(github_token: str):
    auth = Auth.Token(github_token)
    github = Github(auth=auth)
    return github.get_repo(GITHUB_LDC_REPO)


def get_ldc_releases(github_token: str):
    return [
        r
        for r in get_ldc_repo(github_token).get_releases()
        if not r.prerelease and r.published_at >= cutoff_date
    ]


def download_ldc_release_assets(release, cache_dir: Path, github_token: str):
    for asset in release.get_assets():
        if not consider_asset(asset.name):
            continue
        asset_file = cache_dir / asset.name
        if asset_file.exists() and asset_file.stat().st_size == asset.size:
            print(f"{asset.name} is already downloaded.")
            continue
        print(f"Downloading {asset.name}...")
        response = requests.get(
            asset.browser_download_url,
            headers={"Authorization": f"token {github_token}"},
            stream=True,
        )
        response.raise_for_status()

        with open(asset_file, "wb") as f:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                f.write(chunk)

        print(f"Downloaded {asset.name} to {asset_file}.")


def download_ldc_releases(cache_dir: Path, github_token: str):
    assert github_token, "Empty GitHub token"
    for release in get_ldc_releases(github_token):
        download_ldc_release_assets(release, cache_dir, github_token)


def calculate_checksums(cache_dir: Path):
    for f in cache_dir.iterdir():
        if not any(f.name.endswith(ext) for ext in ARCHIVE_FILES):
            continue
        hash = sha256(f.read_bytes())
        print(f"{f.name} sha256 {hash.hexdigest()}")


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
    args = arg_parser.parse_args()
    cache_dir = args.cache
    if not cache_dir.exists() or not cache_dir.is_dir():
        arg_parser.error(f"cache parameter '{cache_dir}' is not a directory")
    if not args.skip_ldc and not args.github_token:
        arg_parser.error("No GitHub token specified")

    if not args.no_refresh:
        if not args.skip_dmd:
            download_dmd_releases(cache_dir)
        if not args.skip_ldc:
            download_ldc_releases(cache_dir, args.github_token)
    calculate_checksums(cache_dir)


if __name__ == "__main__":
    main()
