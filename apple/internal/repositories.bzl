# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Definitions for handling Bazel repositories used by the Apple rules."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

_ZIP_FOUNDATION_BUILD = """\
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ZIPFoundation",
    srcs = glob(["Sources/ZIPFoundation/**/*.swift"]),
    module_name = "ZIPFoundation",
    visibility = ["//visibility:public"],
)
"""

def apple_rules_dependencies():
    """Fetches repositories that are dependencies of the `rules_apple` workspace.
    """

    http_archive(
        name = "xctestrunner",
        urls = [
            "https://github.com/google/xctestrunner/archive/d2ed8cea1af0e33e12acbb69b748877433813a3d.tar.gz",
        ],
        strip_prefix = "xctestrunner-d2ed8cea1af0e33e12acbb69b748877433813a3d",
        sha256 = "6ff20c63f74e8ecdfbae95b894582eece3a6119329236110581cb85e1a5be2b2",
    )

    http_archive(
        name = "zip_foundation",
        urls = [
            "https://github.com/weichsel/ZIPFoundation/archive/refs/tags/0.9.20.tar.gz",
        ],
        strip_prefix = "ZIPFoundation-0.9.20",
        sha256 = "3ddad93f81480d141f15d9b8bdc276a21c5242446c179672c2e787799a423b5e",
        build_file_content = _ZIP_FOUNDATION_BUILD,
    )
