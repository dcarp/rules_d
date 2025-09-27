"""Module extension for integrating dub package manager with Bazel."""

load("//dub/private:packages.bzl", "register_package")

_DEFAULT_PACKAGE_REPO_NAME = "dub"

from_dub_selections = tag_class(attrs = {
    "name": attr.string(doc = """\
Name of the packages repository.
""", default = _DEFAULT_PACKAGE_REPO_NAME),
    "dub_selections_lock": attr.label(doc = """\
Path to the dub package lock file, relative to the module root.
""", mandatory = True, allow_single_file = True),
})

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

def _dub_extension(module_ctx):
    """Registers a dub package repository."""
    for mod in module_ctx.modules:
        for dub_selections in mod.tags.from_dub_selections:
            if dub_selections.name != _DEFAULT_PACKAGE_REPO_NAME and not mod.is_root:
                fail("""\
                Only the root module may override the default name for the dub package repository.
                This prevents conflicting registrations in the global namespace of external repos.
                """)
            dub_repository(
                name = dub_selections.name,
                dub_selections_lock = dub_selections.dub_selections_lock,
            )

dub = module_extension(
    implementation = _dub_extension,
    tag_classes = {"from_dub_selections": from_dub_selections},
)
