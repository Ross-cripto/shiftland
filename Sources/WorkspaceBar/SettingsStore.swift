import Foundation

struct SpacePreference: Identifiable, Equatable {
    let id: String
    var label: String
    var display: String
}

struct ShortcutPreference: Identifiable, Equatable {
    let id: String
    var binding: String
}

struct SettingsDraft {
    fileprivate let document: SettingsDocument
    var spaces: [SpacePreference]
    var shortcuts: [ShortcutPreference]

    var hasChanges: Bool {
        spaces != document.spaces || shortcuts != document.shortcuts
    }
}

enum SettingsError: LocalizedError {
    case unsupported
    case stale
    case invalidLabel
    case invalidDisplay
    case invalidShortcut(String)
    case duplicateShortcut(String)

    var errorDescription: String? {
        switch self {
        case .unsupported: return "No se pudo leer el formato de ajustes de OmniWM."
        case .stale: return "Los ajustes cambiaron en OmniWM. Recarga el archivo antes de guardar."
        case .invalidLabel: return "El nombre de un espacio debe ocupar una sola línea."
        case .invalidDisplay: return "La asignación de pantalla de ese espacio no se puede editar aquí."
        case .invalidShortcut(let binding): return "El atajo «\(binding)» no usa un formato válido como Option+Shift+1."
        case .duplicateShortcut(let binding): return "El atajo «\(binding)» ya está asignado."
        }
    }
}

struct SettingsStore {
    let url: URL

    static var installed: SettingsStore {
        let configuredDirectory = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        let directory = configuredDirectory.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
        return SettingsStore(url: (directory ?? defaultDirectory).appendingPathComponent("omniwm/settings.toml"))
    }

    func load() throws -> SettingsDraft {
        let document = try SettingsDocument(source: String(contentsOf: url, encoding: .utf8))
        return SettingsDraft(document: document, spaces: document.spaces, shortcuts: document.shortcuts)
    }

    func save(_ draft: SettingsDraft) throws -> URL {
        let updated = try draft.document.render(draft)
        let destination = url.resolvingSymlinksInPath()
        let original = Data(draft.document.source.utf8)
        guard try Data(contentsOf: destination) == original else { throw SettingsError.stale }
        let backups = url.deletingLastPathComponent().appendingPathComponent("workspace-bar-backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let backup = backups.appendingPathComponent("settings-\(UUID().uuidString).toml")
        try original.write(to: backup, options: .withoutOverwriting)
        guard try Data(contentsOf: destination) == original else { throw SettingsError.stale }
        try Data(updated.utf8).write(to: destination, options: .atomic)
        return backup
    }
}

private struct TOMLField {
    let line: Int
    let range: Range<String.Index>
    let value: String
}

private struct SettingsSection {
    let lines: ArraySlice<String>

    func field(_ key: String) -> TOMLField? {
        let pattern = #"^\s*"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*("(?:[^"\\]|\\.)*")\s*(?:#.*)?$"#
        guard let match = try? NSRegularExpression(pattern: pattern) else { return nil }
        for index in lines.indices {
            let line = lines[index]
            guard
                let result = match.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                let range = Range(result.range(at: 1), in: line),
                let value = try? JSONDecoder().decode(String.self, from: Data(line[range].utf8))
            else { continue }
            return TOMLField(line: index, range: range, value: value)
        }
        return nil
    }
}

private struct WorkspaceFields {
    let label: TOMLField?
    let display: TOMLField?
    let start: Int
}

fileprivate struct SettingsDocument {
    let source: String
    let spaces: [SpacePreference]
    let shortcuts: [ShortcutPreference]
    let allShortcuts: [ShortcutPreference]
    private let lines: [String]
    private let workspaceFields: [String: WorkspaceFields]
    private let shortcutFields: [String: TOMLField]
    private static let displayRoles = ["main", "secondary"]
    private static let reservedZeroBindings = Set(["option+0", "option+shift+0"])

    init(source: String) throws {
        self.source = source
        let lines = source.components(separatedBy: "\n")
        self.lines = lines
        let sectionStarts = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("[") }
        var spaces: [SpacePreference] = []
        var shortcuts: [ShortcutPreference] = []
        var workspaceFields: [String: WorkspaceFields] = [:]
        var shortcutFields: [String: TOMLField] = [:]

        for (position, start) in sectionStarts.enumerated() {
            let end = position + 1 < sectionStarts.count ? sectionStarts[position + 1] : lines.count
            let section = SettingsSection(lines: lines[(start + 1)..<end])
            let header = lines[start].trimmingCharacters(in: .whitespacesAndNewlines)
            if header == "[[workspaces]]", let name = section.field("name") {
                let label = section.field("displayName")
                let display = Self.monitorField(lines: lines, start: end, sectionStarts: sectionStarts)
                let id = name.value
                guard workspaceFields[id] == nil else { throw SettingsError.unsupported }
                spaces.append(SpacePreference(id: id, label: label?.value ?? id, display: display?.value ?? ""))
                workspaceFields[id] = WorkspaceFields(label: label, display: display, start: start)
            }
            if header == "[[hotkeys]]", let id = section.field("id"), let binding = section.field("binding") {
                guard shortcutFields[id.value] == nil else { throw SettingsError.unsupported }
                shortcuts.append(ShortcutPreference(id: id.value, binding: binding.value))
                shortcutFields[id.value] = binding
            }
        }
        guard !spaces.isEmpty else { throw SettingsError.unsupported }
        self.spaces = spaces
        allShortcuts = shortcuts
        self.shortcuts = shortcuts.filter { Self.isWorkspaceShortcut($0.id) }
        self.workspaceFields = workspaceFields
        self.shortcutFields = shortcutFields
    }

    func render(_ draft: SettingsDraft) throws -> String {
        var edits: [Int: String] = [:]
        var labelsToInsert: [Int: String] = [:]
        for (original, edited) in zip(spaces, draft.spaces) where original != edited {
            guard let fields = workspaceFields[original.id] else { throw SettingsError.unsupported }
            if original.label != edited.label {
                guard !edited.label.isEmpty, edited.label.rangeOfCharacter(from: .controlCharacters) == nil
                else { throw SettingsError.invalidLabel }
                if let label = fields.label {
                    edits[label.line] = try replace(label, with: edited.label)
                } else {
                    labelsToInsert[fields.start] = "displayName = " + (try Self.quoted(edited.label))
                }
            }
            if original.display != edited.display {
                guard let display = fields.display,
                      Self.displayRoles.contains(original.display),
                      Self.displayRoles.contains(edited.display)
                else { throw SettingsError.invalidDisplay }
                edits[display.line] = try replace(display, with: edited.display)
            }
        }

        let bindings = Dictionary(uniqueKeysWithValues: draft.shortcuts.map { ($0.id, $0.binding) })
        for (original, edited) in zip(shortcuts, draft.shortcuts) where original != edited {
            guard ShortcutSyntax.isValid(edited.binding) else { throw SettingsError.invalidShortcut(edited.binding) }
            let normalized = ShortcutSyntax.normalize(edited.binding)
            if Self.reservedZeroBindings.contains(normalized) {
                throw SettingsError.duplicateShortcut(edited.binding)
            }
            if normalized != "none", allShortcuts.contains(where: { candidate in
                candidate.id != edited.id && ShortcutSyntax.normalize(bindings[candidate.id] ?? candidate.binding) == normalized
            }) {
                throw SettingsError.duplicateShortcut(edited.binding)
            }
            guard let field = shortcutFields[edited.id] else { throw SettingsError.unsupported }
            edits[field.line] = try replace(field, with: edited.binding)
        }

        var updated: [String] = []
        for index in lines.indices {
            updated.append(edits[index] ?? lines[index])
            if let label = labelsToInsert[index] { updated.append(label) }
        }
        return updated.joined(separator: "\n")
    }

    private func replace(_ field: TOMLField, with value: String) throws -> String {
        var line = lines[field.line]
        line.replaceSubrange(field.range, with: try Self.quoted(value))
        return line
    }

    private static func quoted(_ value: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func monitorField(lines: [String], start: Int, sectionStarts: [Int]) -> TOMLField? {
        guard start < lines.count,
              lines[start].trimmingCharacters(in: .whitespacesAndNewlines) == "[workspaces.monitorAssignment]"
        else { return nil }
        let end = sectionStarts.first { $0 > start } ?? lines.count
        return SettingsSection(lines: lines[(start + 1)..<end]).field("type")
    }

    private static func isWorkspaceShortcut(_ id: String) -> Bool {
        let actions = ["switchWorkspace.", "moveToWorkspace.", "focus."]
        return actions.contains { id.hasPrefix($0) } || id == "workspaceBackAndForth" || id == "focusPrevious"
    }
}

private enum ShortcutSyntax {
    private static let modifiers = Set(["control", "option", "shift", "command", "fn"])
    private static let namedKeys = Set([
        "left arrow", "right arrow", "up arrow", "down arrow", "tab", "space", "escape",
        "return", "delete", "backspace", "home", "end", "page up", "page down",
        "comma", "period", "slash", "semicolon", "minus", "equal", "grave accent"
    ])

    static func normalize(_ value: String) -> String {
        let parts = tokens(value)
        guard let key = parts.last else { return "" }
        return (parts.dropLast().sorted() + [key]).joined(separator: "+")
    }

    static func isValid(_ value: String) -> Bool {
        let parts = tokens(value)
        if parts == ["none"] { return true }
        guard let key = parts.last, parts.count >= 2 else { return false }
        let requestedModifiers = Set(parts.dropLast())
        return requestedModifiers.count == parts.count - 1
            && requestedModifiers.isSubset(of: modifiers)
            && validKey(key)
    }

    private static func tokens(_ value: String) -> [String] {
        value.lowercased().components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func validKey(_ value: String) -> Bool {
        if namedKeys.contains(value) { return true }
        if value.utf8.count == 1, let byte = value.utf8.first {
            return (48...57).contains(byte) || (97...122).contains(byte)
        }
        guard value.hasPrefix("f"), let number = Int(value.dropFirst()) else { return false }
        return (1...20).contains(number)
    }
}
