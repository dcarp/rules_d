"""Actions that invoke the D compiler."""

DcInfo = provider(
    doc = "D compiler information.",
    fields = {
        "compiler_path": "The path to the D compiler.",
        "import_paths": "Paths (-I) for adding the standard library to the import search paths,",
        "link_paths": "Paths (-L) for adding the standard library to the library search paths,",
    },
)
