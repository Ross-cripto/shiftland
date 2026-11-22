import Foundation
import XCTest
@testable import WorkspaceBar

final class SetupCompatibilityTests: XCTestCase {
    private let sequoia = MacSetupDevice(architecture: .appleSilicon, macOS: .init(major: 15, minor: 5))
    private let tahoe = MacSetupDevice(architecture: .appleSilicon, macOS: .init(major: 26))

    func testDownloadUsesTheDeviceAndSystemVersion() {
        XCTAssertEqual(sequoia.recommendedDownload, .legacy)
        XCTAssertEqual(tahoe.recommendedDownload, .current)
        XCTAssertEqual(MacSetupDevice(architecture: .intel, macOS: .init(major: 26)).recommendedDownload, .legacy)
        XCTAssertNil(MacSetupDevice(architecture: .unknown, macOS: .init(major: 26)).recommendedDownload)
        XCTAssertNil(MacSetupDevice(architecture: .appleSilicon, macOS: .init(major: 14)).recommendedDownload)
    }

    func testSystemVersionsCompareNumericallyAndAcceptApplePlistFormats() {
        XCTAssertEqual(MacOSVersion("15"), .init(major: 15))
        XCTAssertEqual(MacOSVersion("15.5"), .init(major: 15, minor: 5))
        XCTAssertEqual(MacOSVersion("15.5.1"), .init(major: 15, minor: 5, patch: 1))
        XCTAssertTrue(try XCTUnwrap(MacOSVersion("15.10")) > XCTUnwrap(MacOSVersion("15.5")))
        XCTAssertNil(MacOSVersion("15..1"))
        XCTAssertNil(MacOSVersion("15.5 beta"))
    }

    func testACompatibleInstallationInTheHomeDirectoryCanWin() {
        let systemEngine = installation(at: "/Applications/OmniWM.app", minimum: .init(major: 26))
        let homeEngine = installation(at: "/test/Applications/OmniWM.app", minimum: .init(major: 15))
        XCTAssertEqual(OmniInstallation.select([systemEngine, homeEngine], for: sequoia),
                       .available(homeEngine, executable: expectedExecutable(homeEngine)))
    }

    func testRunningInstallationWinsOverAnInactiveCopy() {
        let inactive = installation(at: "/Applications/OmniWM.app", minimum: .init(major: 26))
        let running = installation(at: "/test/Applications/OmniWM.app", minimum: .init(major: 15), running: true)
        XCTAssertEqual(OmniInstallation.select([inactive, running], for: tahoe),
                       .available(running, executable: expectedExecutable(running)))
    }

    func testIncompatibleSystemAndArchitectureAreDistinguished() {
        let engine = installation(at: "/Applications/OmniWM.app", minimum: .init(major: 26),
                                  architectures: [.appleSilicon])
        XCTAssertEqual(OmniInstallation.select([engine], for: sequoia),
                       .incompatible(engine, .requiresMacOS(.init(major: 26))))
        let intel = MacSetupDevice(architecture: .intel, macOS: .init(major: 26))
        XCTAssertEqual(OmniInstallation.select([engine], for: intel), .incompatible(engine, .architecture))
    }

    func testAnIncompleteInstallationIsDifferentFromAMissingOne() {
        let incomplete = installation(at: "/Applications/OmniWM.app", minimum: .init(major: 15), hasCLI: false)
        XCTAssertEqual(OmniInstallation.select([incomplete], for: sequoia), .missingCLI(incomplete))
        XCTAssertEqual(OmniInstallation.select([], for: sequoia), .missing)
    }

    func testSetupSeparatesAStoppedEngineFromIPCAndProtocolFailures() {
        let stopped = installation(at: "/Applications/OmniWM.app", minimum: .init(major: 15))
        let running = installation(at: "/Applications/OmniWM.app", minimum: .init(major: 15), running: true)
        let stoppedState = OmniInstallation.select([stopped], for: sequoia)
        let runningState = OmniInstallation.select([running], for: sequoia)

        XCTAssertEqual(SetupAssessment.failed(OmniError.disconnected, installation: stoppedState).step, .openEngine)
        XCTAssertEqual(SetupAssessment.failed(OmniError.disconnected, installation: runningState).step, .checkIPC)
        XCTAssertEqual(SetupAssessment.failed(OmniError.refused("protocol_mismatch"), installation: runningState).step,
                       .incompatibleIPC)
    }

    func testReadingAnUpdatedBundleRefreshesTheVersionAndRequirements() throws {
        let manager = FileManager.default
        let bundle = manager.temporaryDirectory.appendingPathComponent("OmniWM-\(UUID()).app", isDirectory: true)
        let binaries = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try manager.createDirectory(at: binaries, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: bundle) }
        for name in ["OmniWM", "omniwmctl"] {
            try manager.createSymbolicLink(at: binaries.appendingPathComponent(name),
                                           withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
        }
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        try writeBundleInfo(to: plist, version: "0.5.1", minimum: "15.0")
        let original = try XCTUnwrap(OmniInstallation.read(at: bundle, for: sequoia, isRunning: false))
        XCTAssertEqual(original.version, "0.5.1")
        XCTAssertEqual(original.minimumOS, .init(major: 15))
        XCTAssertNotNil(original.cliURL)

        try writeBundleInfo(to: plist, version: "0.8.0", minimum: "26.0")
        let updated = try XCTUnwrap(OmniInstallation.read(at: bundle, for: sequoia, isRunning: false))
        XCTAssertEqual(updated.version, "0.8.0")
        XCTAssertEqual(OmniInstallation.select([updated], for: sequoia),
                       .incompatible(updated, .requiresMacOS(.init(major: 26))))
    }

    private func writeBundleInfo(to url: URL, version: String, minimum: String) throws {
        let values = [
            "CFBundleIdentifier": "com.barut.OmniWM",
            "CFBundleExecutable": "OmniWM",
            "CFBundleShortVersionString": version,
            "LSMinimumSystemVersion": minimum
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    private func installation(
        at path: String,
        minimum: MacOSVersion,
        architectures: Set<MacArchitecture> = [.appleSilicon, .intel],
        running: Bool = false,
        hasCLI: Bool = true
    ) -> OmniInstallation {
        let bundle = URL(fileURLWithPath: path, isDirectory: true)
        return OmniInstallation(
            bundleURL: bundle,
            version: "0.5.1",
            minimumOS: minimum,
            architectures: architectures,
            cliURL: hasCLI ? bundle.appendingPathComponent("Contents/MacOS/omniwmctl") : nil,
            isRunning: running
        )
    }

    private func expectedExecutable(_ installation: OmniInstallation) -> URL {
        installation.bundleURL.appendingPathComponent("Contents/MacOS/omniwmctl")
    }
}
