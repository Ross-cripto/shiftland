import AppKit
import CoreFoundation
import Darwin
import Foundation

struct MacOSVersion: Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(_ value: String) {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }
        let numbers = components.compactMap { Int($0) }
        guard numbers.count == components.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        self.init(
            major: numbers[0],
            minor: numbers.count > 1 ? numbers[1] : 0,
            patch: numbers.count > 2 ? numbers[2] : 0
        )
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var label: String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }
}

enum MacArchitecture: String, Sendable {
    case appleSilicon = "arm64"
    case intel = "x86_64"
    case unknown

    static var current: Self {
        #if arch(arm64)
        return .appleSilicon
        #elseif arch(x86_64)
        var translated: Int32 = 0
        var size = MemoryLayout.size(ofValue: translated)
        if sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 {
            return translated == 1 ? .appleSilicon : .intel
        }
        return errno == ENOENT ? .intel : .unknown
        #else
        return .unknown
        #endif
    }

    init?(bundleArchitecture: NSNumber) {
        switch bundleArchitecture.intValue {
        case NSBundleExecutableArchitectureARM64: self = .appleSilicon
        case NSBundleExecutableArchitectureX86_64: self = .intel
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .appleSilicon: "Apple Silicon"
        case .intel: "Intel"
        case .unknown: "Arquitectura sin identificar"
        }
    }
}

enum OmniDownload: Equatable, Sendable {
    case legacy
    case current

    static let legacyVersion = "0.5.1"

    var url: URL {
        switch self {
        case .legacy: URL(string: "https://github.com/OmniNull/OmniWM/releases/tag/v\(Self.legacyVersion)")!
        case .current: URL(string: "https://omniwm.app/guides/install/")!
        }
    }

    var buttonTitle: String {
        switch self {
        case .legacy: "Ver OmniWM \(Self.legacyVersion)"
        case .current: "Ver cómo instalar OmniWM"
        }
    }
}

struct MacSetupDevice: Equatable, Sendable {
    private static let minimumOS = MacOSVersion(major: 15)
    private static let currentOmniMinimumOS = MacOSVersion(major: 26)

    let architecture: MacArchitecture
    let macOS: MacOSVersion

    static var current: Self {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Self(
            architecture: .current,
            macOS: MacOSVersion(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion)
        )
    }

    var recommendedDownload: OmniDownload? {
        guard macOS >= Self.minimumOS, architecture != .unknown else { return nil }
        if architecture == .appleSilicon, macOS >= Self.currentOmniMinimumOS { return .current }
        return .legacy
    }
}

enum OmniCompatibilityIssue: Equatable, Sendable {
    case architecture
    case requiresMacOS(MacOSVersion)

    var message: String {
        switch self {
        case .architecture: "Esta copia de OmniWM no incluye la arquitectura de tu Mac."
        case .requiresMacOS(let minimum): "Esta copia de OmniWM requiere macOS \(minimum.label) o posterior."
        }
    }
}

enum OmniInstallationState: Equatable, Sendable {
    case missing
    case missingCLI(OmniInstallation)
    case incompatible(OmniInstallation, OmniCompatibilityIssue)
    case available(OmniInstallation, executable: URL)

    var installation: OmniInstallation? {
        switch self {
        case .missing: nil
        case .missingCLI(let installation), .incompatible(let installation, _), .available(let installation, _):
            installation
        }
    }

    func client() throws -> OmniClient {
        switch self {
        case .missing: throw OmniError.missingEngine
        case .missingCLI: throw OmniError.missingCLI
        case .incompatible(_, let issue): throw OmniError.incompatibleEngine(issue.message)
        case .available(_, let executable): return OmniClient(executable: executable)
        }
    }
}

struct OmniInstallation: Equatable, Sendable {
    private static let bundleIdentifier = "com.barut.OmniWM"

    let bundleURL: URL
    let version: String?
    let minimumOS: MacOSVersion?
    let architectures: Set<MacArchitecture>?
    let cliURL: URL?
    let isRunning: Bool

    @MainActor
    static func installed(for device: MacSetupDevice) -> OmniInstallationState {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        let runningURLs = Set(running.compactMap { $0.bundleURL?.resolvingSymlinksInPath() })
        let standardLocations = [
            URL(fileURLWithPath: "/Applications/OmniWM.app", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/OmniWM.app",
                                                                                    isDirectory: true)
        ]
        let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        let locations = running.compactMap(\.bundleURL) + standardLocations + [registered].compactMap { $0 }
        var installations: [OmniInstallation] = []
        var visited = Set<URL>()
        for location in locations {
            let bundleURL = location.resolvingSymlinksInPath()
            guard visited.insert(bundleURL).inserted,
                  let installation = read(at: bundleURL, for: device, isRunning: runningURLs.contains(bundleURL))
            else { continue }
            installations.append(installation)
        }
        return select(installations, for: device)
    }

    static func read(at bundleURL: URL, for device: MacSetupDevice, isRunning: Bool) -> Self? {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleIdentifier else { return nil }

        let binaryDirectory = bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let cli = binaryDirectory.appendingPathComponent("omniwmctl")
        let app = (info["CFBundleExecutable"] as? String).map { binaryDirectory.appendingPathComponent($0) }
        let fileManager = FileManager.default
        let hasApp = app.map { fileManager.isExecutableFile(atPath: $0.path) } ?? false
        let hasCLI = fileManager.isExecutableFile(atPath: cli.path)
        let appArchitectures = app.flatMap(architectures(at:))
        let cliArchitectures = architectures(at: cli)
        let supportedArchitectures: Set<MacArchitecture>?
        if let appArchitectures, let cliArchitectures {
            supportedArchitectures = appArchitectures.intersection(cliArchitectures)
        } else {
            supportedArchitectures = appArchitectures ?? cliArchitectures
        }

        let declaredMinimum = info["LSMinimumSystemVersion"] as? String
        let architectureMinimums = info["LSMinimumSystemVersionByArchitecture"] as? [String: String]
        let architectureMinimum = architectureMinimums?[device.architecture.rawValue]
        let minimum = [declaredMinimum, architectureMinimum].compactMap { $0.flatMap(MacOSVersion.init) }.max()
        return Self(
            bundleURL: bundleURL,
            version: info["CFBundleShortVersionString"] as? String,
            minimumOS: minimum,
            architectures: supportedArchitectures,
            cliURL: hasApp && hasCLI ? cli : nil,
            isRunning: isRunning
        )
    }

    private static func architectures(at executable: URL) -> Set<MacArchitecture>? {
        guard let types = CFBundleCopyExecutableArchitecturesForURL(executable as CFURL) as? [NSNumber] else {
            return nil
        }
        return Set(types.compactMap(MacArchitecture.init))
    }

    static func select(_ installations: [Self], for device: MacSetupDevice) -> OmniInstallationState {
        if let running = installations.first(where: \.isRunning) { return running.assessment(for: device) }
        var incomplete: OmniInstallationState?
        for installation in installations {
            let assessment = installation.assessment(for: device)
            if case .available = assessment { return assessment }
            if case .missingCLI = assessment, incomplete == nil { incomplete = assessment }
        }
        return incomplete ?? installations.first?.assessment(for: device) ?? .missing
    }

    private func assessment(for device: MacSetupDevice) -> OmniInstallationState {
        if let architectures, device.architecture != .unknown, !architectures.contains(device.architecture) {
            return .incompatible(self, .architecture)
        }
        if let minimumOS, device.macOS < minimumOS {
            return .incompatible(self, .requiresMacOS(minimumOS))
        }
        guard let cliURL else { return .missingCLI(self) }
        return .available(self, executable: cliURL)
    }
}
