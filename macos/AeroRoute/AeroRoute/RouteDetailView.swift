import SwiftUI

struct RouteDetailView: View {
    @ObservedObject var workspace: RouteWorkspace

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
        Group {
#if os(macOS)
            VStack(spacing: 0) {
                RouteMapPane(workspace: workspace)
                Divider()
                FlightLegList(workspace: workspace)
                    .frame(minHeight: 160, idealHeight: 220, maxHeight: 280)
            }
#else
            if horizontalSizeClass == .compact {
                VStack(spacing: 0) {
                    Picker("Route View", selection: $workspace.compactSection) {
                        ForEach(CompactRouteSection.allCases) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    switch workspace.compactSection {
                    case .map:
                        RouteMapPane(workspace: workspace)
                    case .legs:
                        CompactFlightLegList(workspace: workspace)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    RouteMapPane(workspace: workspace)
                        .frame(minHeight: 360)
                    Divider()
                    FlightLegList(workspace: workspace)
                        .frame(minHeight: 220)
                }
            }
#endif
        }
    }
}

private struct RouteMapPane: View {
    @ObservedObject var workspace: RouteWorkspace

    var body: some View {
        ZStack {
            if let svg = workspace.previewSVG {
                SVGPreview(
                    svg: svg,
                    aspectRatio: Double(workspace.settings.designWidth)
                        / Double(workspace.settings.designHeight)
                )
                .padding(12)
            } else if workspace.isRendering {
                ProgressView("Rendering flight map…")
                    .controlSize(.large)
            } else if let error = workspace.renderError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Route Cannot Be Rendered")
                        .font(.headline)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Validate Again") {
                        workspace.validateNow()
                    }
                }
                .padding(20)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "map")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("AeroRoute Preview")
                        .font(.headline)
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.35))
        .dropDestination(for: URL.self) { urls, _ in
            workspace.importURLs(urls)
            return urls.contains { $0.pathExtension.lowercased() == "csv" }
        }
    }
}

private struct FlightLegList: View {
    @ObservedObject var workspace: RouteWorkspace
    @State private var editedLeg: FlightLegSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Flight Information")
                    .font(.headline)
                Spacer()
                Text("Double-click a CSV row to edit airport labels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack(spacing: 12) {
                Text("Flight")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Airports")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Points")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Connection")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)

            Divider()

            List(workspace.legSummaries, selection: $workspace.selectedLegID) { row in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.flightNumber)
                        Text(row.callsign)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(row.origin) → \(row.destination)")
                        if !row.originName.isEmpty || !row.destinationName.isEmpty {
                            Text("\(row.originName.isEmpty ? "—" : row.originName) → \(row.destinationName.isEmpty ? "—" : row.destinationName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(row.pointCount.formatted())
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Label(
                        row.connection,
                        systemImage: row.connects
                            ? "checkmark.circle"
                            : "exclamationmark.triangle"
                    )
                    .foregroundStyle(row.connects ? Color.secondary : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .lineLimit(1)
                .tag(row.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    editedLeg = row
                }
                .contextMenu {
                    Button("Edit Airport Labels…") {
                        editedLeg = row
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("route.legTable")
        .sheet(item: $editedLeg) { row in
            AirportLabelsEditor(workspace: workspace, leg: row)
#if os(macOS)
                .frame(minWidth: 440, minHeight: 300)
#endif
        }
    }
}

private struct AirportLabelsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workspace: RouteWorkspace
    let leg: FlightLegSummary

    @State private var originCode: String
    @State private var originName: String
    @State private var destinationCode: String
    @State private var destinationName: String
    @State private var searchTarget: AirportEndpoint?

    init(workspace: RouteWorkspace, leg: FlightLegSummary) {
        self.workspace = workspace
        self.leg = leg
        let labels = workspace.airportLabels(for: leg.id)
        _originCode = State(initialValue: labels?.origin.code ?? "")
        _originName = State(initialValue: labels?.origin.name ?? "")
        _destinationCode = State(initialValue: labels?.destination.code ?? "")
        _destinationName = State(initialValue: labels?.destination.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Origin") {
                    airportFields(
                        code: $originCode,
                        name: $originName,
                        endpoint: .origin
                    )
                }

                Section("Destination") {
                    airportFields(
                        code: $destinationCode,
                        name: $destinationName,
                        endpoint: .destination
                    )
                }
            }
            .formStyle(.grouped)
            .navigationTitle("\(leg.flightNumber) Airport Labels")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        workspace.updateAirportLabels(
                            for: leg.id,
                            origin: AirportLabel(code: originCode, name: originName),
                            destination: AirportLabel(
                                code: destinationCode,
                                name: destinationName
                            )
                        )
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .sheet(item: $searchTarget) { endpoint in
                AirportSearchPicker(search: workspace.airportSearch) { airport in
                    apply(airport, to: endpoint)
                    searchTarget = nil
                }
#if os(macOS)
                .frame(minWidth: 560, minHeight: 460)
#endif
            }
        }
    }

    @ViewBuilder
    private func airportFields(
        code: Binding<String>,
        name: Binding<String>,
        endpoint: AirportEndpoint
    ) -> some View {
        TextField("Airport Code", text: code)
            .onSubmit {
                autocompleteName(for: code.wrappedValue, name: name)
            }
        TextField("Airport Name", text: name)
        Button("Search Airports…") {
            searchTarget = endpoint
        }
        .disabled(workspace.airportSearch.availability != .ready)
    }

    private func autocompleteName(for code: String, name: Binding<String>) {
        guard let airport = workspace.airportSearch.exactCodeMatch(code) else { return }
        name.wrappedValue = airport.name
    }

    private func apply(_ airport: AirportSearchCandidate, to endpoint: AirportEndpoint) {
        switch endpoint {
        case .origin:
            originCode = airport.code
            originName = airport.name
        case .destination:
            destinationCode = airport.code
            destinationName = airport.name
        }
    }
}

private enum AirportEndpoint: String, Identifiable {
    case origin
    case destination

    var id: Self { self }
}

private struct AirportSearchPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var search: AirportSearchStore
    let onSelect: (AirportSearchCandidate) -> Void

    @State private var query = ""
    @State private var response: AirportSearchSnapshot?
    @State private var alphabeticalAirports: [AirportSearchCandidate] = []
    @State private var selectedAirportID: AirportSearchCandidate.ID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search by code, airport, city, or country", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(12)
                    .onSubmit {
                        lookup(phase: .submitted)
                    }

                Divider()

                switch search.availability {
                case let .unavailable(message):
                    ContentUnavailableView(
                        "Airport Search Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                case .ready:
                    results
                }
            }
            .navigationTitle("Search Airports")
            .onChange(of: query) {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    response = nil
                    selectedAirportID = nil
                } else {
                    lookup(phase: .editing)
                }
            }
            .task {
                alphabeticalAirports = search.airportsAlphabetically()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard let selectedAirport else { return }
                        onSelect(selectedAirport)
                    }
                    .disabled(selectedAirport == nil)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if !displayedAirports.isEmpty {
            List(displayedAirports, selection: $selectedAirportID) { airport in
                AirportSearchResultRow(airport: airport)
                    .tag(airport.id)
            }
        } else if response?.presentation == .noMatches {
            ContentUnavailableView.search(text: query)
        } else {
            ContentUnavailableView(
                "No Airports Available",
                systemImage: "airplane",
                description: Text("Airport data will appear here when it is available.")
            )
        }
    }

    private var displayedAirports: [AirportSearchCandidate] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? alphabeticalAirports
            : response?.candidates ?? []
    }

    private var selectedAirport: AirportSearchCandidate? {
        guard let selectedAirportID else { return nil }
        return displayedAirports.first { $0.id == selectedAirportID }
    }

    private func lookup(phase: AirportSearchQueryPhase) {
        response = search.lookup(text: query, phase: phase)
    }
}

private struct AirportSearchResultRow: View {
    let airport: AirportSearchCandidate

    var body: some View {
        HStack(spacing: 12) {
            Text(countryFlag)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(airport.name)
                Text(location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(airport.code)
                .font(.body.monospaced().weight(.semibold))
                .frame(width: 52, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }

    private var location: String {
        [airport.municipality, airport.countryName]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")
    }

    private var countryFlag: String {
        let scalars = airport.countryCode.uppercased().unicodeScalars
        guard scalars.count == 2,
              scalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else {
            return "🌐"
        }
        return String(String.UnicodeScalarView(
            scalars.compactMap { UnicodeScalar(127_397 + $0.value) }
        ))
    }
}

#if os(iOS)
private struct CompactFlightLegList: View {
    @ObservedObject var workspace: RouteWorkspace

    var body: some View {
        List(workspace.legSummaries, selection: $workspace.selectedLegID) { row in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(row.flightNumber)
                        .font(.headline)
                    Spacer()
                    Text(row.pointCount.formatted())
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Callsign", value: row.callsign)
                LabeledContent("Route", value: "\(row.origin) → \(row.destination)")
                LabeledContent("Connection", value: row.connection)
                    .foregroundStyle(row.connects ? Color.secondary : Color.red)
            }
            .padding(.vertical, 4)
            .tag(row.id)
        }
    }
}
#endif
