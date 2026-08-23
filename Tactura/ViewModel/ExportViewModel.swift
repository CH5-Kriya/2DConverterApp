import SwiftUI
import ReliefCore

@MainActor
@Observable
final class ExportViewModel {

    private let relief: ReliefService

    var projectName: String
    var format: ExportFormat = .stl

    /// The folder the person picked, security-scoped. `nil` means "nowhere
    /// chosen yet", which is a different state from "the default folder" — on
    /// iOS there is no default folder an app may write into.
    private(set) var destination: URL?
    private(set) var stage: ExportStage = .idle

    /// What the export produced, for the summary line after it lands.
    private(set) var summary: String?

    private var task: Task<Void, Never>?

    init(projectName: String, relief: ReliefService) {
        self.projectName = projectName.replacingOccurrences(of: "/", with: "-")
        self.relief = relief
    }

    var fileName: String {
        let trimmed = projectName.trimmingCharacters(in: .whitespaces)
        let base = trimmed.isEmpty ? "relief" : trimmed
        return "\(base).\(format.fileExtension)"
    }

    /// The folder name alone. The mock shows a full path, which iOS will not
    /// hand over for a security-scoped URL — the last component is what a
    /// person actually recognises anyway.
    var destinationLabel: String {
        destination?.lastPathComponent ?? "Choose a folder…"
    }

    var canExport: Bool {
        destination != nil
            && !projectName.trimmingCharacters(in: .whitespaces).isEmpty
            && !stage.isRunning
    }

    func setDestination(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            destination = url
        case .failure(let error):
            stage = .failed(error.localizedDescription)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        stage = .idle
    }

    func dismissResult() {
        stage = .idle
    }

    func export(height: Plane, config: ReliefConfig) {
        guard let destination else { return }
        task?.cancel()

        let started = Date.now
        stage = .running(fraction: 0.02, phase: "Preparing", started: started)

        let relief = self.relief
        let format = self.format
        let fileName = self.fileName

        task = Task { [weak self] in
            do {
                // Mesh building is the long pole — decimation dominates it — so
                // it owns most of the bar. Two coarse phases is all the pipeline
                // reports; inventing finer ones would be theatre.
                await self?.report(0.10, "Building the solid", started)
                let (data, mesh) = await relief.exportPayload(height: height,
                                                              config: config,
                                                              format: format)
                try Task.checkCancellation()
                await self?.report(0.85, "Writing the file", started)

                let url = try Self.write(data, named: fileName, into: destination)
                try Task.checkCancellation()

                await MainActor.run {
                    self?.summary = String(
                        format: "%.0f × %.0f mm · %d faces · %@",
                        mesh.widthMm, mesh.heightMm, mesh.faceCount,
                        mesh.isWatertight ? "watertight" : "NOT watertight")
                    self?.stage = .finished(url)
                }
            } catch is CancellationError {
                await MainActor.run { self?.stage = .idle }
            } catch {
                await MainActor.run { self?.stage = .failed(error.localizedDescription) }
            }
        }
    }

    private func report(_ fraction: Double, _ phase: String, _ started: Date) async {
        await MainActor.run {
            guard self.stage.isRunning || fraction < 0.2 else { return }
            self.stage = .running(fraction: fraction, phase: phase, started: started)
        }
    }

    /// Writing into a folder the person chose means holding its security scope
    /// for exactly as long as the write takes, and no longer.
    private static func write(_ data: Data, named name: String,
                              into folder: URL) throws -> URL {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
