"""Shared attributes"""

def CompilerReleaseInfo(compiler, version, os, arch, url, sha256):
    return struct(
        compiler = compiler,
        version = version,
        os = os,
        arch = arch,
        url = url,
        sha256 = sha256,
    )

d_compilers = ["dmd", "gdc", "ldc"]

default_compiler = d_compilers[0]
default_versions = {
    "dmd": "2.109.1",
    "ldc": "1.40.0",
}

d_toolchain_attrs = {
    "compiler": attr.string(
        default = d_compilers[0],
        doc = "Compiler type. One of: dmd, gdc, ldc",
        values = d_compilers,
    ),
    "version": attr.string(doc = "Compiler version."),
}
