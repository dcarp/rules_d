"""This file is deprecated. Use the definitions in defs.bzl instead."""

def d_binary(*args, **kwargs):  # buildifier: disable=unused-variable
    """Deprecated. Use d_binary from @d_rules//d:defs.bzl instead."""
    fail(
        "@io_bazel_rules_d//d:d.bzl is deprecated. Use d_binary from @d_rules//d:defs.bzl instead.",
    )

def d_docs(*args, **kwargs):  # buildifier: disable=unused-variable
    """Deprecated. d_docs was removed."""
    fail("@io_bazel_rules_d//d:d.bzl is deprecated. d_docs was removed.")

def d_library(*args, **kwargs):  # buildifier: disable=unused-variable
    """Deprecated. Use d_library from @d_rules//d:defs.bzl instead."""
    fail(
        "@io_bazel_rules_d//d:d.bzl is deprecated. Use d_library from @d_rules//d:defs.bzl instead.",
    )

def d_source_library(*args, **kwargs):  # buildifier: disable=unused-variable
    """Deprecated. Use d_library with source_only = True from @d_rules//d:defs.bzl instead."""
    fail(
        "@io_bazel_rules_d//d:d.bzl is deprecated. Use d_library with source_only = True from @d_rules//d:defs.bzl instead.",
    )

def d_test(*args, **kwargs):  # buildifier: disable=unused-variable
    """Deprecated. Use d_test from @d_rules//d:defs.bzl instead."""
    fail(
        "@io_bazel_rules_d//d:d.bzl is deprecated. Use d_test from @d_rules//d:defs.bzl instead.",
    )
