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

public enum BundlerError: Error, CustomStringConvertible, Equatable {
    case bundleConflict(dest: String)
    case bundlePath(dest: String)
    case bundleSymlink(dest: String, target: String)
    case codeSign(exitCode: Int32)
    case postProcessor(exitCode: Int32)
    case missingOutput
    case invalidArchive(message: String)
    case io(message: String)

    public var description: String {
        switch self {
        case .bundleConflict(let dest):
            return "Cannot place two files at the same location '\(dest)' in the bundle"
        case .bundlePath(let dest):
            return "Cannot place bundle entry '\(dest)' outside the bundle root"
        case .bundleSymlink(let dest, let target):
            return "Cannot create bundle symlink '\(dest)' -> '\(target)' because the target escapes the bundle root"
        case .codeSign(let exitCode):
            return "Code signing failed with exit code \(exitCode)"
        case .postProcessor(let exitCode):
            return "Post processor failed with exit code \(exitCode)"
        case .missingOutput:
            return "No output file specified."
        case .invalidArchive(let message):
            return "Invalid archive: \(message)"
        case .io(let message):
            return message
        }
    }
}
