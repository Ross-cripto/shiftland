import SwiftUI

struct SetupAssessment: Equatable {
    enum Step: Equatable {
        case checking
        case install
        case incompatible(OmniCompatibilityIssue)
        case missingCLI
        case openEngine
        case checkIPC
        case incompatibleIPC
        case noWorkspaces
        case connected
    }

    let installation: OmniInstallation?
    let step: Step

    init(_ step: Step, installation: OmniInstallation? = nil) {
        self.installation = installation
        self.step = step
    }

    static func failed(_ error: Error, installation: OmniInstallationState) -> Self {
        switch installation {
        case .missing:
            return Self(.install)
        case .missingCLI(let engine):
            return Self(.missingCLI, installation: engine)
        case .incompatible(let engine, let issue):
            return Self(.incompatible(issue), installation: engine)
        case .available(let engine, _):
            if let error = error as? OmniError {
                switch error {
                case .invalidFrames, .refused("protocol_mismatch"):
                    return Self(.incompatibleIPC, installation: engine)
                default:
                    break
                }
            }
            return Self(engine.isRunning ? .checkIPC : .openEngine, installation: engine)
        }
    }
}

@MainActor
@Observable
final class WorkspaceSetupModel {
    let device: MacSetupDevice
    var assessment = SetupAssessment(.checking)
    var openError: String?

    init(device: MacSetupDevice) {
        self.device = device
    }
}

struct WorkspaceSetupView: View {
    let model: WorkspaceSetupModel
    let recheck: () -> Void
    let openEngine: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Este Mac").foregroundStyle(.secondary)
                    Text("macOS \(model.device.macOS.label) · \(model.device.architecture.label)")
                }
                GridRow {
                    Text("OmniWM").foregroundStyle(.secondary)
                    Text(engineVersion)
                }
            }
            .textSelection(.enabled)

            if let error = model.openError {
                Text(error).foregroundStyle(.red)
            }

            Spacer(minLength: 0)
            HStack {
                if model.assessment.step == .checking {
                    ProgressView().controlSize(.small).accessibilityLabel("Comprobando conexión")
                }
                Spacer()
                if model.assessment.step != .connected {
                    Button("Volver a comprobar", action: recheck)
                        .disabled(model.assessment.step == .checking)
                }
                nextAction
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 245)
    }

    private var engineVersion: String {
        guard let engine = model.assessment.installation else {
            return model.assessment.step == .checking ? "Comprobando…" : "Sin instalar"
        }
        return engine.version ?? "Versión sin identificar"
    }

    private var title: String {
        switch model.assessment.step {
        case .checking: "Comprobando la conexión"
        case .install: model.device.recommendedDownload == nil ? "Comprueba la compatibilidad" : "Instala OmniWM"
        case .incompatible: "Esta copia no es compatible"
        case .missingCLI: "Instalación incompleta"
        case .openEngine: "Abre OmniWM"
        case .checkIPC: "Comprueba la conexión IPC"
        case .incompatibleIPC: "Comprueba la versión de OmniWM"
        case .noWorkspaces: "OmniWM aún no muestra espacios"
        case .connected: "Shiftland está listo"
        }
    }

    private var message: String {
        switch model.assessment.step {
        case .checking:
            "Shiftland está comprobando qué versión de OmniWM puede usar en este Mac."
        case .install:
            downloadAdvice
        case .incompatible(let issue):
            "\(issue.message) \(downloadAdvice)"
        case .missingCLI:
            "La barra necesita la app de OmniWM y su comando omniwmctl. Vuelve a instalar OmniWM. \(downloadAdvice)"
        case .openEngine:
            "Abre la versión instalada y activa IPC en sus ajustes para conectar la barra."
        case .checkIPC:
            "Comprueba que IPC esté activo en los ajustes de OmniWM. Cuando responda, Shiftland se conectará."
        case .incompatibleIPC:
            "La respuesta de OmniWM no coincide con el formato que espera Shiftland. Comprueba la versión instalada y usa el comando incluido en su app."
        case .noWorkspaces:
            "Comprueba los permisos de Accesibilidad y la opción «Las pantallas tienen espacios separados»."
        case .connected:
            "Elige un espacio en la barra para probar el cambio. También puedes revisar tus atajos en Ajustes."
        }
    }

    private var downloadAdvice: String {
        switch model.device.recommendedDownload {
        case .legacy:
            "La descarga de OmniWM \(OmniDownload.legacyVersion) incluye Intel y Apple Silicon y requiere macOS 15 o posterior."
        case .current:
            "Este Mac cumple los requisitos de la versión actual de OmniWM."
        case nil:
            "Consulta los requisitos de macOS y arquitectura antes de instalar OmniWM."
        }
    }

    @ViewBuilder
    private var nextAction: some View {
        switch model.assessment.step {
        case .install, .missingCLI, .incompatible:
            let download = model.device.recommendedDownload
            Link(download?.buttonTitle ?? "Ver requisitos", destination: (download ?? .current).url)
                .buttonStyle(.borderedProminent)
        case .openEngine, .checkIPC, .noWorkspaces:
            Button("Abrir OmniWM", action: openEngine)
                .buttonStyle(.borderedProminent)
        case .incompatibleIPC:
            Link("Ver guía de conexión", destination: URL(string: "https://omniwm.app/reference/cli/overview/")!)
                .buttonStyle(.borderedProminent)
        case .connected:
            Button("Abrir ajustes", action: openSettings)
                .buttonStyle(.borderedProminent)
        case .checking:
            EmptyView()
        }
    }
}
