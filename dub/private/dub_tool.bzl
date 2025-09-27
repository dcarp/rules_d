"""Bazel repository rule for downloading the dub tool.

This makes DUB available before the toolchain registration.
"""

load("//dub/private:versions.bzl", "DUB_VERSIONS")

DUB_DEFAULT_VERSION = "dub-1.40.0"

def _platform_id(repository_ctx):
    """Returns the platform id for the current OS and architecture."""
    os = repository_ctx.os.name
    arch = repository_ctx.os.arch
    if os in ["macos", "osx"]:
        if arch in ["amd64", "x86_64"]:
            return "x86_64-apple-darwin"
        if arch in ["arm64", "aarch64"]:
            return "aarch64-apple-darwin"
    if os == "linux":
        if arch in ["amd64", "x86_64"]:
            return "x86_64-unknown-linux-gnu"
        if arch in ["arm64", "aarch64"]:
            return "aarch64-unknown-linux-gnu"
    if "windows" in os:
        if arch in ["amd64", "x86_64"]:
            return "x86_64-pc-windows-msvc"
        if arch in ["arm64", "aarch64"]:
            return "aarch64-pc-windows-msvc"
    fail("Unsupported OS: {} arch {}".format(os, arch))

def register_dub_tool(repository_ctx):
    """Registers the dub tool as an external repository."""

    dub_version = DUB_VERSIONS[DUB_DEFAULT_VERSION][_platform_id(repository_ctx)]

    repository_ctx.download_and_extract(
        url = dub_version["url"],
        integrity = dub_version["integrity"],
        output = "dub_tool",
    )
