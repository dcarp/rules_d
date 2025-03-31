"""D toolchains"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def d_register_toolchain(compiler, version):
    print("Registering compiler {}-{}".format(compiler, version))
    print("buh!!!!")
