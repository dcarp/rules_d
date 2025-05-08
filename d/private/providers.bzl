"""Module containing definitions of D providers."""

DInfo = provider(
    doc = "Provider containing D compilation information",
    fields = {
        "flags": "List of compiler flags.",
        "linker_flags": "List of linker flags, passed directly to the linker.",
        "imports": "List of import paths.",
        "string_imports": "List of paths for import expressions.",
        "versions": "List of version identifiers.",
    },
)
