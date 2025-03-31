"""Repository rules for D toolchains"""

load(":common.bzl", "d_toolchain_attrs")
load(":known_compiler_releases.bzl", "known_compiler_releases")

def _canonical_arch(arch):
    if arch == "amd64":
        return "x86_64"
    elif arch == "arm64":
        return "aarch64"
    else:
        return arch

def _d_toolchains_repo_impl(repository_ctx):
    os = repository_ctx.os.name
    arch = _canonical_arch(repository_ctx.os.arch)
    compilers = [
        cr
        for cr in known_compiler_releases
        if cr.compiler == repository_ctx.attr.compiler and
           cr.version == repository_ctx.attr.version and
           cr.os == os and
           cr.arch == arch
    ]
    if not compilers:
        fail(
            "No compiler {}-{}-{}-{} found".format(
                repository_ctx.attr.compiler,
                repository_ctx.attr.version,
                os,
                arch,
            ),
        )
    if len(compilers) > 1:
        fail("More than one compiler found")

    compiler = compilers[0]
    print(compiler)
    res = repository_ctx.download_and_extract(url = compiler.url, sha256 = compiler.sha256)
    print(res)

d_toolchains_repo = repository_rule(
    implementation = _d_toolchains_repo_impl,
    attrs = d_toolchain_attrs,
)
