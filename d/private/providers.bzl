"""Module containing definitions of D providers."""

def _dinfo_init(
        *,
        compile_flags = None,
        import_paths = None,
        imports = None,
        libraries = None,
        linker_flags = None,
        source_only = False,
        string_import_paths = None,
        versions = None):
    """Initializes the DInfo provider."""
    return {
        "compile_flags": compile_flags or [],
        "import_paths": import_paths or depset(),
        "imports": imports or depset(),
        "libraries": libraries or depset(),
        "linker_flags": linker_flags or [],
        "source_only": source_only,
        "string_import_paths": string_import_paths or depset(),
        "versions": versions or depset(),
    }

DInfo, _new_dinfo = provider(
    doc = "Provider containing D compilation information",
    fields = {
        "compile_flags": "List of compiler flags.",
        "import_paths": "A depset of import paths.",
        "imports": "A depset of imported D files, transitive import included.",
        "libraries": "A depset of libraries, transitive libraries too.",
        "linker_flags": "List of linker flags, passed directly to the linker.",
        "source_only": "If true, the source files are compiled, but no library is produced.",
        "string_import_paths": "A depset of string import paths.",
        "versions": "A depset of version identifiers.",
    },
    init = _dinfo_init,
)
