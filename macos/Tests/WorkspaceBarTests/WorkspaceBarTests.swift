import Foundation
import XCTest
@testable import WorkspaceBar

final class WorkspaceBarTests: XCTestCase {
    func testFramingPreservesQuotedBracesAndPartialMessages() throws {
        var frames = JSONFrames()
        let first = try frames.append(Data("{\n  \"name\": \"App } \\\" {\",\n".utf8))
        XCTAssertTrue(first.isEmpty)
        let rest = try frames.append(Data("  \"number\": 1\n}\n{\"number\":2}\n".utf8))
        XCTAssertEqual(rest.count, 2)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: rest[0]))
    }

    func testProjectionUsesEngineNamesAndOrdersSlotsNumerically() throws {
        let message = Data("""
        {
          "ok": true, "kind": "event", "channel": "workspace-bar",
          "result": {"payload": {"interactionMonitorId": "display:1", "monitors": [
            {"id": "display:1", "name": "MacBook", "workspaces": [
              {"number": 10, "displayName": "0", "rawName": "10", "isFocused": true, "windows": [
                {"appName": "Finder"}, {"appName": "Finder"}, {"appName": "Zed"}
              ]},
              {"number": 7, "displayName": "7", "rawName": "7", "isFocused": false, "windows": []}
            ]}
          ]}}
        }
        """.utf8)
        let envelope = try JSONDecoder().decode(OmniEnvelope.self, from: message)
        let snapshot = try XCTUnwrap(envelope.result?.payload?.snapshot)
        let workspaces = snapshot.monitors[0].orderedWorkspaces
        XCTAssertEqual(workspaces.map(\.label), ["7", "0"])
        XCTAssertEqual(workspaces[1].rawName, "10")
        XCTAssertEqual(workspaces[1].applicationNames, ["Finder", "Zed"])
    }

    func testProjectionAcceptsNamedWorkspacesWithoutNumbers() throws {
        let data = Data("""
        {"id":"work","number":null,"rawName":"work","displayName":"Work","isFocused":true,
         "windows":[{"appName":"Terminal","bundleId":"com.apple.Terminal","allWindows":[]}]}
        """.utf8)
        let workspace = try JSONDecoder().decode(WorkspaceSlot.self, from: data)
        XCTAssertNil(workspace.number)
        XCTAssertEqual(workspace.id, "work")
        XCTAssertEqual(workspace.label, "Work")
        XCTAssertEqual(workspace.applicationNames, ["Terminal"])
    }

    func testEditingPreservesUnrelatedContentAndBacksUpOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.toml")
        try Data(Self.settings.utf8).write(to: url)
        let store = SettingsStore(url: url)
        var draft = try store.load()
        draft.spaces[0].label = "Trabajo"
        draft.spaces[0].display = "secondary"
        draft.shortcuts[0].binding = "Option+Shift+2"
        let backup = try store.save(draft)
        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(saved.contains("displayName = \"Trabajo\""))
        XCTAssertTrue(saved.contains("type = \"secondary\""))
        XCTAssertTrue(saved.contains("binding = \"Option+Shift+2\" # preserve this"))
        XCTAssertTrue(saved.contains("[[appRules]]\nmatch = \"Finder\""))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), Self.settings)
    }

    func testSaveRejectsAStaleDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.toml")
        try Data(Self.settings.utf8).write(to: url)
        let store = SettingsStore(url: url)
        var draft = try store.load()
        draft.spaces[0].label = "Trabajo"
        try Data((Self.settings + "\n# external change").utf8).write(to: url)
        XCTAssertThrowsError(try store.save(draft))
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).hasSuffix("# external change"))
    }

    func testSaveRejectsBindingsReservedForWorkspaceZero() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.toml")
        try Data(Self.settings.utf8).write(to: url)
        let store = SettingsStore(url: url)
        var draft = try store.load()
        draft.shortcuts[0].binding = "Shift+Option+0"
        XCTAssertThrowsError(try store.save(draft))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), Self.settings)
    }

    static let settings = """
    [general]
    ipcEnabled = true

    [[appRules]]
    match = "Finder"

    [[hotkeys]]
    binding = "Option+1" # preserve this
    id = "switchWorkspace.0"

    [[workspaces]]
    name = "1"

    [workspaces.monitorAssignment]
    type = "main"
    """
}
