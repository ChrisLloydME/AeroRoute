import AeroRouteCore
import Combine
import Foundation
import SwiftUI

struct WorkspaceRenderSettings: Equatable, Sendable {
    var title = ""
    var airportCodes = ""
    var airportNames = ""
    var routeSubtitle = ""

    var showBorders = true
    var showCountryLabels = false
    var showAirportLabels = true
    var showMetadata = true

    var designWidth = 1600
    var designHeight = 1000
    var outputScale = 10.0
    var routeWidth = 1.2

    var oceanColor = "#B2BAC3"
    var landColor = "#D9D9D9"
    var coastlineColor = "#787C80"
    var borderColor = "#A9ADB2"
    var routeColor = "#183143"
    var markerColor = "#E05B45"
    var textColor = "#171D21"
}

struct FlightLegItem: Identifiable, Sendable {
    let id: UUID
    let imported: ImportedLeg
    let sourceIdentity: String

    init(id: UUID = UUID(), imported: ImportedLeg, sourceIdentity: String) {
        self.id = id
        self.imported = imported
        self.sourceIdentity = sourceIdentity
    }

    var source: URL { imported.metadata.source }
    var flightNumber: String { imported.metadata.flightNumber }
    var callsign: String { imported.metadata.callsign }
    var pointCount: Int { imported.metadata.rowCount }
}

struct FlightLegSummary: Identifiable {
    let id: UUID
    let flightNumber: String
    let callsign: String
    let pointCount: Int
    let origin: String
    let destination: String
    let connection: String
    let connects: Bool
}

enum CompactRouteSection: String, CaseIterable, Identifiable {
    case map
    case legs

    var id: Self { self }
    var title: String { self == .map ? "Map" : "Legs" }
    var systemImage: String { self == .map ? "map" : "list.bullet" }
}

@MainActor
final class RouteWorkspace: ObservableObject {
    @Published var legs: [FlightLegItem] = []
    @Published var selectedLegID: FlightLegItem.ID?
    @Published var settings = WorkspaceRenderSettings()

    @Published var previewSVG: String?
    @Published var previewStats: RenderStats?
    @Published var renderError: String?
    @Published var isRendering = false
    @Published var statusMessage = "No files imported"

    @Published var isImporterPresented = false
#if os(macOS)
    @Published var isInspectorPresented = true
#else
    @Published var isInspectorPresented = false
#endif
    @Published var isExporterPresented = false
    @Published var exportDocument: SVGFileDocument?
    @Published var isExporting = false
    @Published var isImporting = false

    @Published var isAlertPresented = false
    @Published var alertTitle = "AeroRoute"
    @Published var alertMessage = ""
    @Published var compactSection = CompactRouteSection.map

    private var renderTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private let renderWorker = RenderWorker()
    private var renderGeneration = 0
    private var exportGeneration = 0
    private var importGeneration = 0
    private var workspaceRevision = 0
    private var loadedCommandLineArguments = false

    deinit {
        renderTask?.cancel()
        exportTask?.cancel()
        importTask?.cancel()
    }

    var documentTitle: String {
        let title = settings.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "AeroRoute" : title
    }

    var suggestedFilename: String {
        let base = documentTitle == "AeroRoute" ? "flight-map" : documentTitle
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = base.components(separatedBy: invalid).joined(separator: "-")
            .replacingOccurrences(of: " · ", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return cleaned.isEmpty ? "flight-map" : cleaned
    }

    var canExport: Bool {
        !legs.isEmpty
            && renderError == nil
            && previewSVG != nil
            && !isImporting
            && !isRendering
            && !isExporting
    }

    var connectionDistances: [Double] {
        let tracks = legs.map(\.imported.track)
        return zip(tracks, tracks.dropFirst()).map(endpointDistanceKM)
    }

    var allLegsConnect: Bool {
        connectionDistances.allSatisfy { $0 <= 50 }
    }

    var legSummaries: [FlightLegSummary] {
        let codes = csvValues(settings.airportCodes)
        let distances = connectionDistances
        return legs.enumerated().map { index, leg in
            let origin = codes.indices.contains(index) ? codes[index] : "—"
            let destination = codes.indices.contains(index + 1) ? codes[index + 1] : "—"
            let isLast = index == legs.count - 1
            let distance = distances.indices.contains(index) ? distances[index] : nil
            return FlightLegSummary(
                id: leg.id,
                flightNumber: leg.flightNumber,
                callsign: leg.callsign.isEmpty ? "—" : leg.callsign,
                pointCount: leg.pointCount,
                origin: origin,
                destination: destination,
                connection: isLast
                    ? "End"
                    : distance.map { String(format: "%.1f km", locale: .posix, $0) } ?? "—",
                connects: isLast || (distance.map { $0 <= 50 } ?? false)
            )
        }
    }

    func importURLs(_ urls: [URL]) {
        let candidates = urls.filter { $0.pathExtension.lowercased() == "csv" }
        guard !candidates.isEmpty else { return }
        guard !isImporting else {
            presentAlert(
                title: "Import in progress",
                message: "Wait for the current CSV import to finish before adding more files."
            )
            return
        }

        let wasEmpty = legs.isEmpty
        importTask?.cancel()
        importGeneration += 1
        let generation = importGeneration
        isImporting = true
        statusMessage = candidates.count == 1
            ? "Importing CSV…"
            : "Importing \(candidates.count) CSV files…"

        importTask = Task { [weak self] in
            guard let self else { return }
            var issues: [String] = []
            var importedAny = false
            var identities = Set(self.legs.map(\.sourceIdentity))

            for source in candidates {
                guard !Task.isCancelled else { break }

                let accessed = source.startAccessingSecurityScopedResource()
                let identity = Self.sourceIdentity(for: source)
                if identities.contains(identity) {
                    if accessed { source.stopAccessingSecurityScopedResource() }
                    continue
                }

                let outcome = await Task.detached(priority: .userInitiated) {
                    Self.loadImport(source)
                }.value
                if accessed { source.stopAccessingSecurityScopedResource() }

                guard !Task.isCancelled, generation == self.importGeneration else {
                    break
                }
                switch outcome {
                case let .success(imported):
                    let item = FlightLegItem(
                        imported: imported,
                        sourceIdentity: identity
                    )
                    self.legs.append(item)
                    self.selectedLegID = item.id
                    identities.insert(identity)
                    importedAny = true
                case let .failure(message):
                    issues.append("\(source.lastPathComponent): \(message)")
                }
            }

            guard !Task.isCancelled, generation == self.importGeneration else { return }
            self.importTask = nil
            self.isImporting = false
            if wasEmpty,
               importedAny,
               self.settings.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let numbers = self.legs.map(\.flightNumber)
                self.settings.title = numbers.count == 1
                    ? numbers[0]
                    : numbers.joined(separator: " · ")
            }
            if !issues.isEmpty {
                self.presentAlert(
                    title: "Some files were not imported",
                    message: issues.joined(separator: "\n\n")
                )
            }
            self.scheduleRender()
        }
    }

    func removeSelectedLeg() {
        guard let selectedLegID,
              let index = legs.firstIndex(where: { $0.id == selectedLegID }) else {
            return
        }
        legs.remove(at: index)
        if legs.isEmpty {
            self.selectedLegID = nil
        } else {
            self.selectedLegID = legs[min(index, legs.count - 1)].id
        }
        scheduleRender()
    }

    func removeLegs(at offsets: IndexSet) {
        let selected = selectedLegID
        legs.remove(atOffsets: offsets)
        if let selected, !legs.contains(where: { $0.id == selected }) {
            selectedLegID = legs.first?.id
        }
        scheduleRender()
    }

    func clear() {
        importTask?.cancel()
        importTask = nil
        importGeneration += 1
        isImporting = false

        renderTask?.cancel()
        renderTask = nil
        renderGeneration += 1
        isRendering = false

        invalidateExport()
        workspaceRevision += 1
        legs.removeAll()
        selectedLegID = nil
        previewSVG = nil
        previewStats = nil
        renderError = nil
        statusMessage = "No files imported"
    }

    func moveLegs(from source: IndexSet, to destination: Int) {
        legs.move(fromOffsets: source, toOffset: destination)
        scheduleRender()
    }

    func moveSelectedLeg(by offset: Int) {
        guard let selectedLegID,
              let current = legs.firstIndex(where: { $0.id == selectedLegID }) else {
            return
        }
        let destination = current + offset
        guard legs.indices.contains(destination) else { return }
        legs.swapAt(current, destination)
        scheduleRender()
    }

    func scheduleRender() {
        renderTask?.cancel()
        renderGeneration += 1
        workspaceRevision += 1
        invalidateExport()
        let generation = renderGeneration

        guard !legs.isEmpty else {
            previewSVG = nil
            previewStats = nil
            renderError = nil
            isRendering = false
            statusMessage = "No files imported"
            return
        }

        let tracks = legs.map(\.imported.track)
        let options = renderOptions(preview: true)
        let style = mapStyle
        let sourceName = documentTitle
        let worker = renderWorker
        isRendering = true
        renderError = nil
        statusMessage = "Rendering preview…"

        renderTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }
            let outcome = await worker.render(
                tracks: tracks,
                sourceName: sourceName,
                options: options,
                style: style
            )
            guard !Task.isCancelled,
                  let self,
                  generation == self.renderGeneration else { return }
            self.isRendering = false
            switch outcome {
            case let .success(svg, stats):
                self.previewSVG = svg
                self.previewStats = stats
                self.renderError = nil
                self.statusMessage = self.readyStatus(stats: stats)
            case let .failure(message):
                self.previewSVG = nil
                self.previewStats = nil
                self.renderError = message
                self.statusMessage = message
            case .cancelled:
                break
            }
        }
    }

    func validateNow() {
        scheduleRender()
    }

    func prepareExport() {
        guard !legs.isEmpty else { return }
        exportTask?.cancel()
        exportGeneration += 1
        let generation = exportGeneration
        let revision = workspaceRevision
        let tracks = legs.map(\.imported.track)
        let options = renderOptions(preview: false)
        let style = mapStyle
        let sourceName = documentTitle
        let worker = renderWorker
        exportDocument = nil
        isExporting = true
        statusMessage = "Preparing SVG…"

        exportTask = Task { [weak self] in
            let outcome = await worker.render(
                tracks: tracks,
                sourceName: sourceName,
                options: options,
                style: style
            )
            guard !Task.isCancelled,
                  let self,
                  generation == self.exportGeneration,
                  revision == self.workspaceRevision else { return }
            self.exportTask = nil
            self.isExporting = false
            switch outcome {
            case let .success(svg, stats):
                self.exportDocument = SVGFileDocument(svg: svg)
                self.statusMessage = self.readyStatus(stats: stats)
                self.isExporterPresented = true
            case let .failure(message):
                self.presentAlert(title: "Cannot export", message: message)
                self.statusMessage = message
            case .cancelled:
                break
            }
        }
    }

    func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            statusMessage = "Exported \(url.lastPathComponent)"
            exportDocument = nil
        case let .failure(error):
            presentAlert(title: "Export failed", message: Self.message(for: error))
        }
    }

    func loadCommandLineArgumentsIfNeeded() {
        guard !loadedCommandLineArguments else { return }
        loadedCommandLineArguments = true

        let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
        var files: [URL] = []
        var overrides: [(String, String)] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.lowercased().hasSuffix(".csv") {
                files.append(URL(fileURLWithPath: argument))
            } else if [
                "--title", "--waypoint-codes", "--waypoint-names", "--route-name",
            ].contains(argument), index + 1 < arguments.count {
                overrides.append((argument, arguments[index + 1]))
                index += 1
            }
            index += 1
        }
        if !files.isEmpty {
            importURLs(files)
        }
        for (option, value) in overrides {
            switch option {
            case "--title": settings.title = value
            case "--waypoint-codes": settings.airportCodes = value
            case "--waypoint-names": settings.airportNames = value
            case "--route-name": settings.routeSubtitle = value
            default: break
            }
        }
        if !overrides.isEmpty {
            scheduleRender()
        }
    }

    func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        isAlertPresented = true
    }

    func renderOptions(preview: Bool) -> RenderOptions {
        RenderOptions(
            width: settings.designWidth,
            height: settings.designHeight,
            scale: preview ? 1 : settings.outputScale,
            showBorders: settings.showBorders,
            showCountryLabels: settings.showCountryLabels,
            showAirports: settings.showAirportLabels,
            showFlightNumber: settings.showMetadata,
            flightNumber: nonempty(settings.title),
            waypointCodes: csvValues(settings.airportCodes),
            waypointNames: csvValues(settings.airportNames),
            routeName: nonempty(settings.routeSubtitle)
        )
    }

    var mapStyle: MapStyle {
        MapStyle(
            ocean: settings.oceanColor,
            land: settings.landColor,
            coastline: settings.coastlineColor,
            borders: settings.borderColor,
            route: settings.routeColor,
            marker: settings.markerColor,
            text: settings.textColor,
            routeWidth: settings.routeWidth
        )
    }

    private func readyStatus(stats: RenderStats) -> String {
        let legLabel = legs.count == 1 ? "1 leg" : "\(legs.count) legs"
        let validation = legs.count > 1 ? "All legs connect · " : ""
        return validation + "\(legLabel) · \(stats.sourcePoints.formatted()) source points · "
            + "\(stats.curveSegments.formatted()) cubic segments"
    }

    private func csvValues(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func invalidateExport() {
        exportTask?.cancel()
        exportTask = nil
        exportGeneration += 1
        isExporting = false
        isExporterPresented = false
        exportDocument = nil
    }

    nonisolated fileprivate static func render(
        tracks: [Track],
        sourceName: String,
        options: RenderOptions,
        style: MapStyle
    ) -> RenderOutcome {
        do {
            let track: Track
            if tracks.count == 1 {
                track = tracks[0]
            } else {
                track = try combineTracks(
                    tracks: tracks,
                    source: URL(fileURLWithPath: sourceName),
                    validateContinuity: true
                )
            }
            let rendered = try SVGRenderer.buildSVG(
                track: track,
                options: options,
                style: style
            )
            return .success(rendered.svg, rendered.stats)
        } catch {
            return .failure(message(for: error))
        }
    }

    nonisolated private static func loadImport(_ source: URL) -> ImportOutcome {
        do {
            return .success(try loadFR24(source))
        } catch {
            return .failure(message(for: error))
        }
    }

    nonisolated private static func sourceIdentity(for source: URL) -> String {
        if let values = try? source.resourceValues(forKeys: [.fileResourceIdentifierKey]),
           let identifier = values.fileResourceIdentifier {
            return String(describing: identifier)
        }
        return source.standardizedFileURL.path
    }

    nonisolated private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

private enum ImportOutcome: Sendable {
    case success(ImportedLeg)
    case failure(String)
}

private enum RenderOutcome: Sendable {
    case success(String, RenderStats)
    case failure(String)
    case cancelled
}

private actor RenderWorker {
    func render(
        tracks: [Track],
        sourceName: String,
        options: RenderOptions,
        style: MapStyle
    ) -> RenderOutcome {
        guard !Task.isCancelled else { return .cancelled }
        let outcome = RouteWorkspace.render(
            tracks: tracks,
            sourceName: sourceName,
            options: options,
            style: style
        )
        return Task.isCancelled ? .cancelled : outcome
    }
}

private extension Locale {
    static let posix = Locale(identifier: "en_US_POSIX")
}
