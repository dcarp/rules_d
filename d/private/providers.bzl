"""Module containing definitions of D providers."""

def _dinfo_init(
        *,
        dynamic_libraries = None,
        expression_imports = None,
        flags = None,
        imports = None,
        linker_flags = None,
        source_only = False,
        static_libraries = None,
        versions = None):
    """Initializes the DInfo provider."""
    return {
        "dynamic_libraries": dynamic_libraries or [],
        "expression_imports": expression_imports or [],
        "flags": flags or [],
        "imports": imports or [],
        "linker_flags": linker_flags or [],
        "source_only": source_only,
        "static_libraries": static_libraries or [],
        "versions": versions or [],
    }

DInfo, _new_dinfo = provider(
    doc = "Provider containing D compilation information",
    fields = {
        "dynamic_libraries": "List of dynamic library files.",
        "expression_imports": "List of paths for import expressions.",
        "flags": "List of compiler flags.",
        "imports": "List of import paths.",
        "linker_flags": "List of linker flags, passed directly to the linker.",
        "source_only": "If true, the source files are compiled, but no library is produced.",
        "static_libraries": "List of static library files.",
        "versions": "List of version identifiers.",
    },
    init = _dinfo_init,
)
