"""WORKSPACE APIs for integrating dub package manager with Bazel."""

load("//dub/private:packages.bzl", "register_package")

def _dub_repository_impl(repository_ctx):
    """Creates a dub package repository."""
    dub_selections_lock = json.decode(repository_ctx.read(repository_ctx.attr.dub_selections_lock))
    for package, package_info in dub_selections_lock.get("packages", {}).items():
        package_info["name"] = package
        repository_ctx.report_progress("Registering dub package {}({})".format(package, package_info.get("version")))
        register_package(repository_ctx, package_info)

dub_repository = repository_rule(
    implementation = _dub_repository_impl,
    attrs = {
        "dub_selections_lock": attr.label(mandatory = True, allow_single_file = True),
    },
)

def d_register_dub_repository(
        dub_selections_lock,
        name = "dub"):
    """Registers a repository containing packages from dub.selections.lock.json.

    Args:
        dub_selections_lock: Path to the dub package lock file.
        name: Name of the generated repository. Defaults to "dub".
    """
    dub_repository(
        name = name,
        dub_selections_lock = dub_selections_lock,
    )
