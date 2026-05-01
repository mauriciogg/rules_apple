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
import Darwin
import Foundation
import XCTest
import ZIPFoundation

final class BundlerExperimentalTests: XCTestCase {

    private var scratchDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratchDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bundlerExperimentalScratch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratchDir, FileManager.default.fileExists(atPath: scratchDir.path) {
            try FileManager.default.removeItem(at: scratchDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func runBundler(
        bundleMergeFiles: [BundleMergeFile] = [],
        bundleMergeZips: [BundleMergeZip] = []
    ) throws -> URL {
        let outputURL = scratchDir.appendingPathComponent("output")
        let control = BundleControl(
            bundleMergeFiles: bundleMergeFiles,
            bundleMergeZips: bundleMergeZips,
            output: outputURL.path
        )
        try Bundler(control: control).run()
        return outputURL
    }

    @discardableResult
    private func scratchFile(_ relativePath: String, content: String = "") throws -> URL {
        let url = scratchDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    private func scratchSymlink(_ relativePath: String, target: String) throws -> URL {
        let url = scratchDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
        return url
    }

    private enum ZipFixtureEntry {
        case file(name: String, content: String)
        case symlink(name: String, target: String)
    }

    private func makeZip(at url: URL, entries: [ZipFixtureEntry]) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let archive = try Archive(url: url, accessMode: .create)
        for entry in entries {
            switch entry {
            case let .file(name, content):
                let data = Data(content.utf8)
                try archive.addEntry(
                    with: name,
                    type: .file,
                    uncompressedSize: Int64(data.count),
                    compressionMethod: .none,
                    provider: { position, size in
                        return data.subdata(in: Int(position)..<Int(position) + size)
                    }
                )
            case let .symlink(name, target):
                let data = Data(target.utf8)
                try archive.addEntry(
                    with: name,
                    type: .symlink,
                    uncompressedSize: Int64(data.count),
                    compressionMethod: .none,
                    provider: { position, size in
                        return data.subdata(in: Int(position)..<Int(position) + size)
                    }
                )
            }
        }
    }

    private func makeFrameworkZip(at url: URL) throws {
        try makeZip(at: url, entries: [
            .file(name: "Foo.framework/Versions/A/Foo", content: "framework-binary"),
            .file(name: "Foo.framework/Versions/A/Resources/Info.plist", content: "plist-content"),
            .symlink(name: "Foo.framework/Versions/Current", target: "A"),
            .symlink(name: "Foo.framework/Foo", target: "Versions/Current/Foo"),
            .symlink(name: "Foo.framework/Resources", target: "Versions/Current/Resources"),
        ])
    }

    private func assertSymlink(
        _ url: URL,
        target: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var statBuf = stat()
        XCTAssertEqual(lstat(url.path, &statBuf), 0, "\(url.path) should exist", file: file, line: line)
        XCTAssertEqual(
            (statBuf.st_mode & S_IFMT), S_IFLNK,
            "\(url.path) should be a symlink", file: file, line: line
        )
        let resolved = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? ""
        XCTAssertEqual(resolved, target, file: file, line: line)
    }

    private func assertIsFile(_ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        XCTAssertTrue(exists, "\(url.path) should exist", file: file, line: line)
        XCTAssertFalse(isDir.boolValue, "\(url.path) should be a file", file: file, line: line)
    }

    // MARK: - Tests

    func testBundleMergeFilesPreservesSymlinkedFilesAndDirectories() throws {
        let frameworkRoot = scratchDir.appendingPathComponent("Foo.framework")
        try scratchFile("Foo.framework/Versions/A/Foo", content: "framework-binary")
        try scratchFile("Foo.framework/Versions/A/Resources/Info.plist", content: "plist-content")
        try scratchSymlink("Foo.framework/Versions/Current", target: "A")
        try scratchSymlink("Foo.framework/Foo", target: "Versions/Current/Foo")
        try scratchSymlink("Foo.framework/Resources", target: "Versions/Current/Resources")

        let output = try runBundler(bundleMergeFiles: [
            BundleMergeFile(src: frameworkRoot.path, dest: "Contents/Frameworks/Foo.framework"),
        ])

        let bundled = output.appendingPathComponent("Contents/Frameworks/Foo.framework")
        assertIsFile(bundled.appendingPathComponent("Versions/A/Foo"))
        assertIsFile(bundled.appendingPathComponent("Versions/A/Resources/Info.plist"))
        assertSymlink(bundled.appendingPathComponent("Versions/Current"), target: "A")
        assertSymlink(bundled.appendingPathComponent("Foo"), target: "Versions/Current/Foo")
        assertSymlink(bundled.appendingPathComponent("Resources"), target: "Versions/Current/Resources")
    }

    func testBundleMergeZipsPreservesSymlinkEntries() throws {
        let zipURL = scratchDir.appendingPathComponent("Foo.zip")
        try makeFrameworkZip(at: zipURL)

        let output = try runBundler(bundleMergeZips: [
            BundleMergeZip(src: zipURL.path, dest: "Contents/Frameworks"),
        ])

        let bundled = output.appendingPathComponent("Contents/Frameworks/Foo.framework")
        assertIsFile(bundled.appendingPathComponent("Versions/A/Foo"))
        assertIsFile(bundled.appendingPathComponent("Versions/A/Resources/Info.plist"))
        assertSymlink(bundled.appendingPathComponent("Versions/Current"), target: "A")
        assertSymlink(bundled.appendingPathComponent("Foo"), target: "Versions/Current/Foo")
        assertSymlink(bundled.appendingPathComponent("Resources"), target: "Versions/Current/Resources")
    }

    func testBundleMergeZipsRejectsAbsoluteSymlinkTargets() throws {
        let zipURL = scratchDir.appendingPathComponent("Foo.zip")
        try makeZip(at: zipURL, entries: [
            .symlink(name: "Foo.framework/Foo", target: "/tmp/outside"),
        ])

        XCTAssertThrowsError(try runBundler(bundleMergeZips: [
            BundleMergeZip(src: zipURL.path, dest: "Contents/Frameworks"),
        ])) { error in
            guard case BundlerError.bundleSymlink = error else {
                XCTFail("Expected bundleSymlink error, got: \(error)")
                return
            }
        }
    }

    func testBundleMergeZipsRejectsRelativeSymlinkTargetsThatEscape() throws {
        let zipURL = scratchDir.appendingPathComponent("Foo.zip")
        try makeZip(at: zipURL, entries: [
            .symlink(name: "Foo.framework/Foo", target: "../../../../outside"),
        ])

        XCTAssertThrowsError(try runBundler(bundleMergeZips: [
            BundleMergeZip(src: zipURL.path, dest: "Contents/Frameworks"),
        ])) { error in
            guard case BundlerError.bundleSymlink = error else {
                XCTFail("Expected bundleSymlink error, got: \(error)")
                return
            }
        }
    }

    func testBundleMergeZipsRejectsWritesThroughEscapingSymlinkAncestors() throws {
        let zipURL = scratchDir.appendingPathComponent("Foo.zip")
        try makeZip(at: zipURL, entries: [
            .symlink(name: "Foo", target: "bar"),
            .file(name: "bar/.keep", content: ""),
            .file(name: "Foo/Contents/file.txt", content: "payload"),
        ])

        let output = try runBundler(bundleMergeZips: [
            BundleMergeZip(src: zipURL.path, dest: ""),
        ])
        assertSymlink(output.appendingPathComponent("Foo"), target: "bar")
        assertIsFile(output.appendingPathComponent("bar/Contents/file.txt"))

        let escapingURL = scratchDir.appendingPathComponent("Escaping.zip")
        try makeZip(at: escapingURL, entries: [
            .symlink(name: "Foo", target: "../outside"),
            .file(name: "Foo/Contents/file.txt", content: "payload"),
        ])

        XCTAssertThrowsError(try runBundler(bundleMergeZips: [
            BundleMergeZip(src: escapingURL.path, dest: ""),
        ])) { error in
            guard case BundlerError.bundleSymlink = error else {
                XCTFail("Expected bundleSymlink error, got: \(error)")
                return
            }
        }
    }
}
