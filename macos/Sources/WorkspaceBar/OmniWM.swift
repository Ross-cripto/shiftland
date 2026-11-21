import Foundation

struct WorkspaceSnapshot: Equatable, Sendable {
    let monitors: [WorkspaceMonitor]
    let interactionMonitorId: String?
}

struct WorkspaceMonitor: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let workspaces: [WorkspaceSlot]

    var orderedWorkspaces: [WorkspaceSlot] {
        workspaces.sorted { $0.number < $1.number }
    }
}

struct WorkspaceSlot: Decodable, Equatable, Sendable, Identifiable {
    struct Window: Decodable, Equatable, Sendable {
        let appName: String
    }

    let number: Int
    let displayName: String?
    let rawName: String
    let isFocused: Bool
    let windows: [Window]

    var id: Int { number }

    var label: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return String(number)
    }

    var applicationNames: [String] {
        var names: [String] = []
        for window in windows where !names.contains(window.appName) {
            names.append(window.appName)
        }
        return names
    }
}

struct OmniEnvelope: Decodable {
    struct Result: Decodable {
        let payload: Payload?
    }

    struct Payload: Decodable {
        let monitors: [WorkspaceMonitor]?
        let interactionMonitorId: String?

        var snapshot: WorkspaceSnapshot? {
            guard let monitors else { return nil }
            return WorkspaceSnapshot(monitors: monitors, interactionMonitorId: interactionMonitorId)
        }
    }

    let ok: Bool
    let status: String?
    let result: Result?
}

enum OmniError: LocalizedError {
    case missingEngine
    case disconnected
    case refused(String)
    case invalidFrames

    var errorDescription: String? {
        switch self {
        case .missingEngine: return "OmniWM.app no está instalado."
        case .disconnected: return "OmniWM no responde. Comprueba que está abierto y que IPC está activo."
        case .refused(let status): return "OmniWM rechazó el comando (\(status))."
        case .invalidFrames: return "OmniWM envió una respuesta que la barra no pudo leer."
        }
    }
}

struct JSONFrames {
    private static let maximumFrameBytes = 4 * 1024 * 1024
    private var message = Data()
    private var depth = 0
    private var insideString = false
    private var escape = false

    mutating func append(_ data: Data) throws -> [Data] {
        var messages: [Data] = []
        for byte in data {
            if depth == 0 {
                if [9, 10, 13, 32].contains(byte) { continue }
                guard byte == 123 else { throw OmniError.invalidFrames }
                message = Data([byte])
                depth = 1
                continue
            }
            message.append(byte)
            guard message.count <= Self.maximumFrameBytes else { throw OmniError.invalidFrames }
            if insideString {
                consumeStringByte(byte)
                continue
            }
            switch byte {
            case 34: insideString = true
            case 123: depth += 1
            case 125:
                depth -= 1
                if depth == 0 { messages.append(message) }
            default: break
            }
        }
        return messages
    }

    private mutating func consumeStringByte(_ byte: UInt8) {
        if escape {
            escape = false
        } else if byte == 92 {
            escape = true
        } else if byte == 34 {
            insideString = false
        }
    }
}

struct OmniClient: Sendable {
    let executable: URL

    static func installed() throws -> OmniClient {
        let applicationPaths = [
            "/Applications/OmniWM.app",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/OmniWM.app").path
        ]
        for applicationPath in applicationPaths {
            let executable = URL(fileURLWithPath: applicationPath)
                .appendingPathComponent("Contents/MacOS/omniwmctl")
            if FileManager.default.isExecutableFile(atPath: executable.path) {
                return OmniClient(executable: executable)
            }
        }
        throw OmniError.missingEngine
    }

    func snapshots() -> AsyncThrowingStream<WorkspaceSnapshot, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let reader = Task {
                do {
                    var frames = JSONFrames()
                    for try await data in output(["subscribe", "workspace-bar,display-changed"]) {
                        for message in try frames.append(data) {
                            let response = try Self.response(message)
                            if let snapshot = response.result?.payload?.snapshot {
                                continuation.yield(snapshot)
                            }
                        }
                    }
                    continuation.finish(throwing: OmniError.disconnected)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }

    func command(_ arguments: [String]) async throws {
        _ = try await request(arguments)
    }

    func snapshot() async throws -> WorkspaceSnapshot {
        let response = try await request(["query", "workspace-bar"])
        guard let snapshot = response.result?.payload?.snapshot else { throw OmniError.invalidFrames }
        return snapshot
    }

    private func request(_ arguments: [String]) async throws -> OmniEnvelope {
        var frames = JSONFrames()
        for try await data in output(arguments) {
            if let message = try frames.append(data).first {
                return try Self.response(message)
            }
        }
        throw OmniError.disconnected
    }

    private static func response(_ data: Data) throws -> OmniEnvelope {
        let response = try JSONDecoder().decode(OmniEnvelope.self, from: data)
        if response.ok || response.status == "no_change" { return response }
        throw OmniError.refused(response.status ?? "IPC")
    }

    private func output(_ arguments: [String]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            let pipe = Pipe()
            let reader = pipe.fileHandleForReading
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            continuation.onTermination = { _ in
                reader.readabilityHandler = nil
                if process.isRunning { process.terminate() }
            }
            reader.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
