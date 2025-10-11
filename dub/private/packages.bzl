"""Dub package registration."""

load("@bazel_skylib//lib:paths.bzl", "paths")

def register_package(repository_ctx, package):
    """Registers a dub package as an external repository.

    Args:
        repository_ctx: The repository context.
        package: A dictionary with the package information from the dub.selections.lock file.
    """

    repository_ctx.download_and_extract(
        url = package["url"],
        integrity = package["integrity"],
        stripPrefix = "{}-{}".format(package["name"], package["version"]),
        output = package["name"],
    )
    result = repository_ctx.execute(
        [repository_ctx.path("dub_tool/dub"), "describe"],
        working_directory = package["name"],
    )
    if result.return_code != 0:
        fail("Failed to run dub describe for package {}: {}".format(package["name"], result.stderr))
    package_metadata = json.decode(result.stdout)

    bazel_build_content = "load(\"@rules_d//d:defs.bzl\", \"d_library\")\n"
    for target in package_metadata["targets"]:
        build_info = target["buildSettings"]
        target_path = build_info["targetPath"]
        if target["rootConfiguration"] == "library":
            srcs = [paths.relativize(src, target_path) for src in build_info["sourceFiles"]]
            imports = [paths.relativize(imp, target_path) for imp in build_info["importPaths"]]
            target_definition = """
d_library(
    name = "{name}",
    srcs = {srcs},
    versions = {versions},
    deps = {deps},
    imports = {imports},
    visibility = ["//visibility:public"],
)
""".format(
                name = build_info["targetName"],
                srcs = srcs,
                versions = build_info["versions"],
                deps = [],
                imports = imports,
            )
            bazel_build_content += target_definition

    repository_ctx.file(package["name"] + "/BUILD.bazel", bazel_build_content, executable = False)
