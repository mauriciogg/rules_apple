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

/// Subset of POSIX shell tokenization, covering the cases produced by
/// `shlex.split` for code-signing command lines: whitespace separation,
/// single-quoted runs (verbatim), double-quoted runs (backslash escape
/// supported), and backslash-escaped characters outside quotes.
enum ShellLexer {
    static func split(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasContent = false
        var quote: Character? = nil
        var escape = false

        for c in s {
            if escape {
                current.append(c)
                escape = false
                hasContent = true
                continue
            }
            if let q = quote {
                if c == "\\" && q == "\"" {
                    escape = true
                    continue
                }
                if c == q {
                    quote = nil
                    continue
                }
                current.append(c)
                continue
            }
            if c == "\\" {
                escape = true
                continue
            }
            if c == "'" || c == "\"" {
                quote = c
                hasContent = true
                continue
            }
            if c.isWhitespace {
                if hasContent {
                    tokens.append(current)
                    current = ""
                    hasContent = false
                }
                continue
            }
            current.append(c)
            hasContent = true
        }
        if hasContent {
            tokens.append(current)
        }
        return tokens
    }
}
