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

import Bundler
import Foundation

@main
struct BundletoolExperimentalTool {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 1 else {
            FileHandle.standardError.write(
                Data("ERROR: Expected path to control file and nothing else.\n".utf8)
            )
            exit(1)
        }

        let controlURL = URL(fileURLWithPath: args[0])
        do {
            let data = try Data(contentsOf: controlURL)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let control = try decoder.decode(BundleControl.self, from: data)
            try Bundler(control: control).run()
        } catch let error as BundlerError {
            FileHandle.standardError.write(Data("ERROR: \(error.description)\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
            exit(1)
        }
    }
}
