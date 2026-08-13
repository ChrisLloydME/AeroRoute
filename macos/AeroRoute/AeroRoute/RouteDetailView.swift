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
    @State private var selectedAirportID: AirportSearchCandidate.ID?

    var body: some View {
        Group {
            switch search.availability {
            case .loading:
                ProgressView("Loading airports…")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: query) {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                response = nil
                selectedAirportID = nil
            } else {
                lookup(phase: .editing)
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
            .airportPickerChrome(
                text: $query,
                canApply: selectedAirport != nil,
                onSearch: { lookup(phase: .submitted) },
                onCancel: { dismiss() },
                onApply: applySelection
            )
        } else if !trimmedQuery.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No airports match “\(trimmedQuery)”.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .airportPickerChrome(
                text: $query,
                canApply: false,
                onSearch: { lookup(phase: .submitted) },
                onCancel: { dismiss() },
                onApply: applySelection
            )
        } else {
            ContentUnavailableView(
                "No Airports Available",
                systemImage: "airplane",
                description: Text("Airport data will appear here when it is available.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .airportPickerChrome(
                text: $query,
                canApply: false,
                onSearch: { lookup(phase: .submitted) },
                onCancel: { dismiss() },
                onApply: applySelection
            )
        }
    }

    private var displayedAirports: [AirportSearchCandidate] {
        trimmedQuery.isEmpty
            ? search.airportsAlphabetically()
            : response?.candidates ?? []
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedAirport: AirportSearchCandidate? {
        guard let selectedAirportID else { return nil }
        return displayedAirports.first { $0.id == selectedAirportID }
    }

    private func lookup(phase: AirportSearchQueryPhase) {
        response = search.lookup(text: query, phase: phase)
    }

    private func applySelection() {
        guard let selectedAirport else { return }
        onSelect(selectedAirport)
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

struct AirportSearchField: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Code, airport, city, or country", text: $text)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("airport.searchField")
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .airportSearchFieldBackground()
    }
}

private extension View {
    @ViewBuilder
    func airportSearchFieldBackground() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func airportPickerChrome(
        text: Binding<String>,
        canApply: Bool,
        onSearch: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onApply: @escaping () -> Void
    ) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0) {
                AirportSearchField(text: text, onSubmit: onSearch)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                AirportPickerActionBar(
                    canApply: canApply,
                    onCancel: onCancel,
                    onApply: onApply
                )
                .padding(.vertical, 16)
            }
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            safeAreaInset(edge: .top, spacing: 0) {
                AirportSearchField(text: text, onSubmit: onSearch)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AirportPickerActionBar(
                    canApply: canApply,
                    onCancel: onCancel,
                    onApply: onApply
                )
                .padding(.vertical, 16)
                .background(.bar)
            }
        }
    }
}

private struct AirportPickerActionBar: View {
    let canApply: Bool
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            cancelButton
            applyButton
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var cancelButton: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.glass)
        } else {
            Button("Cancel", action: onCancel)
        }
    }

    @ViewBuilder
    private var applyButton: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Button("Apply", action: onApply)
                .buttonStyle(.glassProminent)
                .disabled(!canApply)
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Apply", action: onApply)
                .disabled(!canApply)
                .keyboardShortcut(.defaultAction)
        }
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
