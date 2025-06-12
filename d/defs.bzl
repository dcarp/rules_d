"Public API of D rules."

load("//d/private/rules:library.bzl", _d_library = "d_library")
load("//d/private/rules:test.bzl", _d_test = "d_test")

d_library = _d_library
d_test = _d_test
