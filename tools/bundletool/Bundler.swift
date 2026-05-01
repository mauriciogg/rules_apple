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
import ZIPFoundation

/// Implements the file-system bundling logic for Apple bundles. This is the
/// experimental tree-artifact bundler that combines bundling, post-processing
/// and signing into a single action.
public final class Bundler {

    private let control: BundleControl
    private var useClonefile: Bool = true

    public init(control: BundleControl) {
        self.control = control
    }

    public func run() throws {
        guard let outputPath = control.output, !outputPath.isEmpty else {
            throw BundlerError.missingOutput
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        let fm = FileManager.default

        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }
        try createDirectoryIfNeeded(at: outputURL)

        for zip in control.bundleMergeZips ?? [] {
            try addZipContents(src: URL(fileURLWithPath: zip.src), dest: zip.dest, bundleRoot: outputURL)
        }

        for file in control.bundleMergeFiles ?? [] {
            try addFiles(
                src: URL(fileURLWithPath: file.src),
                dest: file.dest,
                executable: file.executable ?? false,
                bundleRoot: outputURL
            )
        }

        try setMode(0o755, atPath: outputURL.path)

        if let postProcessor = control.postProcessor, !postProcessor.isEmpty {
            try postProcessBundle(bundleRoot: outputURL, postProcessor: postProcessor)
        }

        if let signing = control.codeSigningCommands, !signing.isEmpty {
            try signBundle(bundleRoot: outputURL, commandLines: signing)
        }
    }

    // MARK: - File merging

    private func addFiles(src: URL, dest: String, executable: Bool, bundleRoot: URL) throws {
        switch lstatKind(of: src.path) {
        case .symlink:
            // A top-level symlink-to-directory and a broken symlink are
            // preserved as symlinks; a symlink-to-file is dereferenced and
            // copied as a regular file.
            var followed = stat()
            let targetExists = stat(src.path, &followed) == 0
            if !targetExists || (followed.st_mode & S_IFMT) == S_IFDIR {
                try copySymlink(src: src, dest: dest, bundleRoot: bundleRoot)
            } else {
                try copyFile(src: src, dest: dest, executable: executable, bundleRoot: bundleRoot)
            }
        case .directory:
            try walkDirectoryAndAdd(src: src, dest: dest, executable: executable, bundleRoot: bundleRoot)
        case .regular:
            try copyFile(src: src, dest: dest, executable: executable, bundleRoot: bundleRoot)
        case .missing, .other:
            return
        }
    }

    private func walkDirectoryAndAdd(src: URL, dest: String, executable: Bool, bundleRoot: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: src.path).sorted()
        for name in names {
            let childSrc = src.appendingPathComponent(name)
            let childDest = (dest as NSString).appendingPathComponent(name)
            let kind = lstatKind(of: childSrc.path)
            switch kind {
            case .symlink:
                try copySymlink(src: childSrc, dest: childDest, bundleRoot: bundleRoot)
            case .directory:
                try walkDirectoryAndAdd(
                    src: childSrc,
                    dest: childDest,
                    executable: executable,
                    bundleRoot: bundleRoot
                )
            case .regular:
                try copyFile(src: childSrc, dest: childDest, executable: executable, bundleRoot: bundleRoot)
            case .missing, .other:
                continue
            }
        }
    }

    private func addZipContents(src: URL, dest: String, bundleRoot: URL) throws {
        if src.pathExtension == "app" {
            // .app bundles are copied wholesale, preserving symlinks.
            let appName = src.lastPathComponent
            let destURL = bundleRoot.appendingPathComponent(dest).appendingPathComponent(appName)
            try createDirectoryIfNeeded(at: destURL.deletingLastPathComponent())
            try FileManager.default.copyItem(at: src, to: destURL)
            return
        }

        let archive = try Archive(url: src, accessMode: .read)
        for entry in archive {
            let entryDest = PathUtils.normalize((dest as NSString).appendingPathComponent(entry.path))
            switch entry.type {
            case .directory:
                continue
            case .symlink:
                let target = try readEntryAsString(archive: archive, entry: entry)
                try writeSymlink(dest: entryDest, target: target, bundleRoot: bundleRoot)
            case .file:
                let data = try readEntryAsData(archive: archive, entry: entry)
                let executable = (entry.posixPermissions & 0o111) != 0
                try writeEntry(dest: entryDest, data: data, executable: executable, bundleRoot: bundleRoot)
            }
        }
    }

    private func readEntryAsData(archive: Archive, entry: Entry) throws -> Data {
        var buffer = Data()
        buffer.reserveCapacity(Int(entry.uncompressedSize))
        _ = try archive.extract(entry, skipCRC32: true) { buffer.append($0) }
        return buffer
    }

    private func readEntryAsString(archive: Archive, entry: Entry) throws -> String {
        let data = try readEntryAsData(archive: archive, entry: entry)
        guard let string = String(data: data, encoding: .utf8) else {
            throw BundlerError.invalidArchive(message: "ZIP entry '\(entry.path)' is not valid UTF-8")
        }
        return string
    }

    // MARK: - Writing primitives

    private func copySymlink(src: URL, dest: String, bundleRoot: URL) throws {
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: src.path)
        try writeSymlink(dest: dest, target: target, bundleRoot: bundleRoot)
    }

    private func copyFile(src: URL, dest: String, executable: Bool, bundleRoot: URL) throws {
        let fullDest = bundleRoot.appendingPathComponent(dest)
        try validateDestInBundle(fullDest: fullDest, bundleRoot: bundleRoot, dest: dest)

        let fm = FileManager.default
        if fm.fileExists(atPath: fullDest.path) && !isSymlink(at: fullDest.path) {
            if !fm.contentsEqual(atPath: fullDest.path, andPath: src.path) {
                throw BundlerError.bundleConflict(dest: dest)
            }
            try setMode(executable ? 0o755 : 0o644, atPath: fullDest.path)
            return
        }

        try createDirectoryIfNeeded(at: fullDest.deletingLastPathComponent())

        if useClonefile {
            let result = src.path.withCString { srcPtr -> Int32 in
                return fullDest.path.withCString { destPtr in
                    return clonefile(srcPtr, destPtr, 0)
                }
            }
            if result != 0 {
                let err = errno
                if err == EXDEV || err == ENOTSUP {
                    useClonefile = false
                    if fm.fileExists(atPath: fullDest.path) {
                        try fm.removeItem(at: fullDest)
                    }
                    try fm.copyItem(at: src, to: fullDest)
                } else {
                    throw BundlerError.io(message: "failed to clonefile \(src.path) to \(fullDest.path)")
                }
            }
        } else {
            if fm.fileExists(atPath: fullDest.path) {
                try fm.removeItem(at: fullDest)
            }
            try fm.copyItem(at: src, to: fullDest)
        }

        try setMode(executable ? 0o755 : 0o644, atPath: fullDest.path)
    }

    private func writeSymlink(dest: String, target: String, bundleRoot: URL) throws {
        let fullDest = bundleRoot.appendingPathComponent(dest)
        try validateDestInBundle(fullDest: fullDest, bundleRoot: bundleRoot, dest: dest)
        try validateSymlinkTarget(fullDest: fullDest, target: target, bundleRoot: bundleRoot, dest: dest)

        let fm = FileManager.default
        if pathOrSymlinkExists(at: fullDest.path) {
            if !isSymlink(at: fullDest.path) {
                throw BundlerError.bundleConflict(dest: dest)
            }
            let existingTarget = try fm.destinationOfSymbolicLink(atPath: fullDest.path)
            if existingTarget != target {
                throw BundlerError.bundleConflict(dest: dest)
            }
            return
        }

        try createDirectoryIfNeeded(at: fullDest.deletingLastPathComponent())
        try fm.createSymbolicLink(atPath: fullDest.path, withDestinationPath: target)
    }

    private func writeEntry(dest: String, data: Data, executable: Bool, bundleRoot: URL) throws {
        let fullDest = bundleRoot.appendingPathComponent(dest)
        try validateDestInBundle(fullDest: fullDest, bundleRoot: bundleRoot, dest: dest)

        let fm = FileManager.default
        if fm.fileExists(atPath: fullDest.path) && !isSymlink(at: fullDest.path) {
            let existing = try Data(contentsOf: fullDest)
            if existing != data {
                throw BundlerError.bundleConflict(dest: dest)
            }
        }

        try createDirectoryIfNeeded(at: fullDest.deletingLastPathComponent())
        try data.write(to: fullDest, options: [.atomic])
        try setMode(executable ? 0o755 : 0o644, atPath: fullDest.path)
    }

    // MARK: - Validation

    private func validateDestInBundle(fullDest: URL, bundleRoot: URL, dest: String) throws {
        let bundleRootReal = PathUtils.realpath(bundleRoot.path)
        let destReal = PathUtils.realpath(fullDest.path)
        if PathUtils.commonPath(bundleRootReal, destReal) != bundleRootReal {
            throw BundlerError.bundlePath(dest: dest)
        }
    }

    private func validateSymlinkTarget(fullDest: URL, target: String, bundleRoot: URL, dest: String) throws {
        if target.hasPrefix("/") {
            throw BundlerError.bundleSymlink(dest: dest, target: target)
        }
        let bundleRootReal = PathUtils.realpath(bundleRoot.path)
        let parent = fullDest.deletingLastPathComponent().path
        let joined = (parent as NSString).appendingPathComponent(target)
        let normalized = PathUtils.normalize(joined)
        let targetReal = PathUtils.realpath(normalized)
        if PathUtils.commonPath(bundleRootReal, targetReal) != bundleRootReal {
            throw BundlerError.bundleSymlink(dest: dest, target: target)
        }
    }

    // MARK: - Filesystem helpers

    private func createDirectoryIfNeeded(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private enum FileKind {
        case symlink
        case directory
        case regular
        case missing
        case other
    }

    private func lstatKind(of path: String) -> FileKind {
        var statBuf = stat()
        if lstat(path, &statBuf) != 0 {
            return .missing
        }
        switch statBuf.st_mode & S_IFMT {
        case S_IFLNK: return .symlink
        case S_IFDIR: return .directory
        case S_IFREG: return .regular
        default: return .other
        }
    }

    private func isSymlink(at path: String) -> Bool {
        var statBuf = stat()
        guard lstat(path, &statBuf) == 0 else { return false }
        return (statBuf.st_mode & S_IFMT) == S_IFLNK
    }

    private func pathOrSymlinkExists(at path: String) -> Bool {
        var statBuf = stat()
        return lstat(path, &statBuf) == 0
    }

    private func setMode(_ mode: mode_t, atPath path: String) throws {
        if Darwin.chmod(path, mode) != 0 {
            let err = errno
            throw BundlerError.io(message: "chmod failed for \(path): \(String(cString: strerror(err)))")
        }
    }

    // MARK: - Post-processing and signing

    private func postProcessBundle(bundleRoot: URL, postProcessor: String) throws {
        let workDir = bundleRoot.deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: postProcessor)
        process.arguments = [workDir.path]
        var env = ProcessInfo.processInfo.environment
        env["TREE_ARTIFACT_OUTPUT"] = bundleRoot.path
        process.environment = env

        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw BundlerError.postProcessor(exitCode: process.terminationStatus)
        }
    }

    private func signBundle(bundleRoot: URL, commandLines: String) throws {
        for line in commandLines.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let argv = ShellLexer.split(String(line)).map {
                $0.replacingOccurrences(of: "$WORK_DIR", with: bundleRoot.path)
            }
            guard let exe = argv.first else { continue }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: exe)
            process.arguments = Array(argv.dropFirst())
            process.environment = [:]

            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw BundlerError.codeSign(exitCode: process.terminationStatus)
            }
        }
    }
}

private extension Entry {
    /// Convenience accessor for the Unix mode bits stored in the entry's
    /// `external file attributes`. Defaults to `0o644` when unset.
    var posixPermissions: Int {
        (fileAttributes[.posixPermissions] as? Int) ?? 0o644
    }
}
