load("@build_bazel_rules_swift//swift:swift.bzl", "swift_binary", "swift_library", "swift_test")
load("@rules_python//python:py_binary.bzl", "py_binary")
load("@rules_python//python:py_library.bzl", "py_library")
load("@rules_python//python:py_test.bzl", "py_test")

licenses(["notice"])

py_binary(
    name = "bundletool",
    srcs = ["bundletool.py"],
    python_version = "PY3",
    srcs_version = "PY3",
    visibility = [
        "//apple/internal:__pkg__",
    ],
    deps = [":bundletool_lib"],
)

py_library(
    name = "bundletool_lib",
    srcs = [
        "__init__.py",
        "bundletool.py",
    ],
    srcs_version = "PY3",
)

py_test(
    name = "bundletool_test",
    srcs = ["bundletool_test.py"],
    python_version = "PY3",
    deps = [":bundletool_lib"],
)

swift_library(
    name = "Bundler",
    srcs = [
        "BundleControl.swift",
        "Bundler.swift",
        "BundlerError.swift",
        "PathUtils.swift",
        "ShellLexer.swift",
    ],
    module_name = "Bundler",
    deps = ["@zip_foundation//:ZIPFoundation"],
)

swift_binary(
    name = "bundletool_experimental",
    srcs = ["BundletoolExperimentalTool.swift"],
    visibility = [
        "//apple/internal:__pkg__",
    ],
    deps = [":Bundler"],
)

swift_test(
    name = "bundletool_experimental_test",
    srcs = ["BundlerExperimentalTests.swift"],
    deps = [
        ":Bundler",
        "@zip_foundation//:ZIPFoundation",
    ],
)

filegroup(
    name = "process_and_sign_template",
    srcs = ["process_and_sign.sh.template"],
    visibility = [
        "//apple/internal:__pkg__",
    ],
)

# Consumed by bazel tests.
filegroup(
    name = "for_bazel_tests",
    testonly = True,
    srcs = glob(["**"]),
    visibility = [
        "//tools:__pkg__",
    ],
)
