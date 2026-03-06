"""Module extension for integrating dub package manager with Bazel."""

load("//dub:repositories.bzl", "dub_repository")

_DEFAULT_PACKAGE_REPO_NAME = "dub"

from_dub_selections = tag_class(attrs = {
    "name": attr.string(doc = """\
Name of the packages repository.
""", default = _DEFAULT_PACKAGE_REPO_NAME),
    "dub_selections_lock": attr.label(doc = """\
Path to the dub package lock file, relative to the module root.
""", mandatory = True, allow_single_file = True),
})

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
