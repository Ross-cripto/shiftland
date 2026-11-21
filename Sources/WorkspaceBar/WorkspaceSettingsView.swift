import SwiftUI

struct WorkspaceSettingsView: View {
    let store: SettingsStore
    let preview: Bool
    @State private var draft: SettingsDraft?
    @State private var operationMessage: String?
    @State private var operationFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let draft = Binding($draft) {
                TabView {
                    spaces(draft.spaces)
                        .tabItem { Label("Espacios", systemImage: "square.grid.2x2") }
                    displays(draft.spaces)
                        .tabItem { Label("Pantallas", systemImage: "display.2") }
                    shortcuts(draft.shortcuts)
                        .tabItem { Label("Atajos", systemImage: "keyboard") }
                }
            } else {
                Spacer()
                ContentUnavailableView("Ajustes no disponibles", systemImage: "gearshape",
                                       description: Text("Comprueba que OmniWM tiene un archivo de ajustes."))
                Spacer()
            }
            if let operationMessage {
                Text(operationMessage)
                    .foregroundStyle(operationFailed ? Color.red : Color.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Text(preview ? "Vista previa · guardado desactivado" : "Los cambios se guardan en OmniWM")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
                Button("Recargar", action: load)
                Button("Guardar", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview || draft?.hasChanges != true)
            }
        }
        .padding(20)
        .frame(minWidth: 515, minHeight: 442)
        .onAppear(perform: load)
    }

    private func spaces(_ spaces: Binding<[SpacePreference]>) -> some View {
        Form {
            Section("Nombres en la barra") {
                ForEach(spaces) { space in
                    let id = space.wrappedValue.id
                    let number = id == "10" ? "0" : id
                    TextField("Espacio \(number)", text: space.label)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func displays(_ spaces: Binding<[SpacePreference]>) -> some View {
        Form {
            Section("Pantalla asignada") {
                ForEach(spaces) { space in
                    let value = space.wrappedValue
                    if value.display == "main" || value.display == "secondary" {
                        Picker("Espacio \(value.label)", selection: space.display) {
                            Text("Principal").tag("main")
                            Text("Secundaria").tag("secondary")
                        }
                    } else {
                        LabeledContent("Espacio \(value.label)", value: value.display.isEmpty ? "Automática" : value.display)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func shortcuts(_ shortcuts: Binding<[ShortcutPreference]>) -> some View {
        Form {
            Section("Cambiar de espacio, mover y enfocar ventanas") {
                ForEach(shortcuts) { shortcut in
                    TextField(shortcutTitle(shortcut.wrappedValue.id), text: shortcut.binding)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Ir al espacio 0", value: "⌥ 0")
                LabeledContent("Mover al espacio 0", value: "⌥ ⇧ 0")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutTitle(_ id: String) -> String {
        let parts = id.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2, let index = Int(parts[1]) {
            if parts[0] == "switchWorkspace" { return "Ir al espacio \(index + 1)" }
            if parts[0] == "moveToWorkspace" { return "Mover al espacio \(index + 1)" }
        }
        switch id {
        case "focus.left": return "Enfocar a la izquierda"
        case "focus.right": return "Enfocar a la derecha"
        case "focus.up": return "Enfocar arriba"
        case "focus.down": return "Enfocar abajo"
        case "focusPrevious": return "Enfocar ventana anterior"
        case "workspaceBackAndForth": return "Espacio anterior"
        case "switchWorkspace.next": return "Espacio siguiente"
        case "switchWorkspace.previous": return "Espacio anterior en orden"
        case "moveToWorkspace.up": return "Mover al espacio de arriba"
        case "moveToWorkspace.down": return "Mover al espacio de abajo"
        default: return id
        }
    }

    private func load() {
        do {
            draft = try store.load()
            operationMessage = nil
            operationFailed = false
        } catch {
            operationMessage = error.localizedDescription
            operationFailed = true
        }
    }

    private func save() {
        guard let draft, !preview, draft.hasChanges else { return }
        do {
            _ = try store.save(draft)
            self.draft = try store.load()
            operationMessage = "Ajustes guardados. Se creó una copia anterior."
            operationFailed = false
        } catch {
            operationMessage = error.localizedDescription
            operationFailed = true
        }
    }
}
