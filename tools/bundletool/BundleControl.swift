// Copyright 2026 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

public struct BundleMergeFile: Codable {
    public let src: String
    public let dest: String
    public let executable: Bool?

    public init(src: String, dest: String, executable: Bool? = nil) {
        self.src = src
        self.dest = dest
        self.executable = executable
    }
}

public struct BundleMergeZip: Codable {
    public let src: String
    public let dest: String

    public init(src: String, dest: String) {
        self.src = src
        self.dest = dest
    }
}

/// Decoded representation of the bundler's JSON control file. The on-disk
/// format uses snake_case keys; callers that decode JSON should set
/// `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`.
public struct BundleControl: Codable {
    public let bundleMergeFiles: [BundleMergeFile]?
    public let bundleMergeZips: [BundleMergeZip]?
    public let codeSigningCommands: String?
    public let output: String?
    public let postProcessor: String?

    public init(
        bundleMergeFiles: [BundleMergeFile]? = nil,
        bundleMergeZips: [BundleMergeZip]? = nil,
        codeSigningCommands: String? = nil,
        output: String? = nil,
        postProcessor: String? = nil
    ) {
        self.bundleMergeFiles = bundleMergeFiles
        self.bundleMergeZips = bundleMergeZips
        self.codeSigningCommands = codeSigningCommands
        self.output = output
        self.postProcessor = postProcessor
    }
}
