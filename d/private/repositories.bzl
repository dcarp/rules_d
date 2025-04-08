"""Repository rules for D toolchains"""

load(":common.bzl", "d_toolchain_attrs")
load(":known_compiler_releases.bzl", "known_compiler_releases")

def _canonical_cpu(cpu):
    if cpu == "amd64":
        return "x86_64"
    elif cpu == "arm64":
        return "aarch64"
    else:
        return cpu

def _canonical_os(os):
    if os == "mac os x":
        return "macos"
    else:
        return os

def _archive_prefix(url):
    filename = url.rsplit("/", 1)[-1]
    if filename.startswith("dmd"):
        return "dmd2"
    elif filename.startswith("ldc"):
        for ext in [".tar.xz", ".zip"]:
            if filename.endswith(ext):
                return filename[:-len(ext)]
        return filename
    else:
        fail("Unknown compiler archive %s" % filename)

def _d_toolchains_repo_impl(repository_ctx):
    os = _canonical_os(repository_ctx.os.name)
    cpu = _canonical_cpu(repository_ctx.os.arch)
    compilers = [
        cr
        for cr in known_compiler_releases
        if cr.compiler == repository_ctx.attr.compiler and
           cr.version == repository_ctx.attr.version and
           cr.os == os and
           cr.cpu == cpu
    ]
    if not compilers:
        fail(
            "%s version %s not available for %s/%s" %
            (repository_ctx.attr.compiler, repository_ctx.attr.version, os, cpu),
        )
    if len(compilers) > 1:
        fail("More than one compiler found")

    compiler = compilers[0]
    repository_ctx.download_and_extract(
        url = compiler.url,
        sha256 = compiler.sha256,
        strip_prefix = _archive_prefix(compiler.url),
    )
    if repository_ctx.attr._toolchain_build_file:
        toolchain_build_file = repository_ctx.attr._toolchain_build_file
    else:
        toolchain_build_file = Label(":BUILD.%s_toolchain.bazel" % repository_ctx.attr.compiler)

    repository_ctx.file(
        "BUILD.bazel",
        repository_ctx.read(repository_ctx.path(toolchain_build_file)),
        executable = False,
    )

d_toolchains_repo = repository_rule(
    implementation = _d_toolchains_repo_impl,
    attrs = d_toolchain_attrs,
)
