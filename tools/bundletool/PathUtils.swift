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

import Darwin
import Foundation

enum PathUtils {

    /// Mimics Python's `os.path.realpath`: resolves symlinks and normalizes
    /// `.`/`..` segments. Handles non-existent path tails by leaving them
    /// unresolved at the end.
    static func realpath(_ path: String) -> String {
        var seen: Set<String> = []
        return resolve(path, seen: &seen, depth: 0)
    }

    /// Returns the longest common ancestor directory of two absolute paths,
    /// matching Python's `os.path.commonpath` for our use case.
    static func commonPath(_ a: String, _ b: String) -> String {
        let aParts = a.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let bParts = b.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var common = "/"
        for (x, y) in zip(aParts, bParts) {
            if x == y {
                common = common == "/" ? "/\(x)" : "\(common)/\(x)"
            } else {
                break
            }
        }
        return common
    }

    /// Mimics Python's `os.path.normpath`: collapses `.` and `..` segments
    /// without touching the filesystem.
    static func normalize(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var stack: [String] = []
        for part in parts {
            if part == "." {
                continue
            }
            if part == ".." {
                if let last = stack.last, last != ".." {
                    stack.removeLast()
                } else if !isAbsolute {
                    stack.append(part)
                }
                continue
            }
            stack.append(part)
        }
        let joined = stack.joined(separator: "/")
        if isAbsolute {
            return "/" + joined
        }
        return joined.isEmpty ? "." : joined
    }

    private static func resolve(_ path: String, seen: inout Set<String>, depth: Int) -> String {
        if depth > 40 {
            return path
        }

        let absolute: String
        if path.hasPrefix("/") {
            absolute = path
        } else {
            absolute = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(path)
        }

        let parts = absolute.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var resolved = "/"

        for (i, part) in parts.enumerated() {
            if part == "." {
                continue
            }
            if part == ".." {
                if resolved != "/" {
                    let parent = (resolved as NSString).deletingLastPathComponent
                    resolved = parent.isEmpty ? "/" : parent
                }
                continue
            }

            let candidate = resolved == "/" ? "/\(part)" : "\(resolved)/\(part)"

            var statBuf = stat()
            if lstat(candidate, &statBuf) != 0 {
                var rem = candidate
                if i + 1 < parts.count {
                    for r in parts[(i + 1)...] {
                        rem = (rem as NSString).appendingPathComponent(r)
                    }
                }
                return normalize(rem)
            }

            if (statBuf.st_mode & S_IFMT) == S_IFLNK {
                if seen.contains(candidate) {
                    resolved = candidate
                    continue
                }
                seen.insert(candidate)

                let bufferSize = Int(PATH_MAX) + 1
                var buffer = [CChar](repeating: 0, count: bufferSize)
                let len = readlink(candidate, &buffer, bufferSize - 1)
                if len <= 0 {
                    resolved = candidate
                    continue
                }
                buffer[Int(len)] = 0
                let target = String(cString: buffer)

                let absoluteTarget: String
                if target.hasPrefix("/") {
                    absoluteTarget = target
                } else {
                    let parent = resolved
                    absoluteTarget = parent == "/" ? "/\(target)" : "\(parent)/\(target)"
                }

                resolved = resolve(absoluteTarget, seen: &seen, depth: depth + 1)
            } else {
                resolved = candidate
            }
        }

        return resolved
    }
}
