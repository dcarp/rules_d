"""Public API for DUB rules."""

load("//dub/private/selections_lock:selections_lock.bzl", _dub_lock_dependencies = "dub_lock_dependencies")

dub_lock_dependencies = _dub_lock_dependencies
