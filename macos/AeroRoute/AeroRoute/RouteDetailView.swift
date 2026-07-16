import SwiftUI

struct RouteDetailView: View {
    @ObservedObject var workspace: RouteWorkspace

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
        Group {
#if os(macOS)
            VSplitView {
                RouteMapPane(workspace: workspace)
                    .frame(minHeight: 380)
                FlightLegTable(workspace: workspace)
                    .frame(minHeight: 170, idealHeight: 230)
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
                    FlightLegTable(workspace: workspace)
                        .frame(minHeight: 220)
                }
            }
#endif
        }
#if os(macOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RouteStatusBar(workspace: workspace)
        }
#endif
    }
}

#if os(macOS)
private struct RouteStatusBar: View {
    @ObservedObject var workspace: RouteWorkspace

    var body: some View {
        HStack(spacing: 6) {
            if workspace.isRendering || workspace.isExporting {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(
                    systemName: workspace.renderError == nil
                        ? "checkmark.circle"
                        : "exclamationmark.triangle"
                )
            }
            Text(workspace.statusMessage)
                .lineLimit(1)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(workspace.renderError == nil ? Color.secondary : Color.red)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}
#endif

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
                ContentUnavailableView {
                    Label("Route Cannot Be Rendered", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Validate Again") {
                        workspace.validateNow()
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Import Flight Tracks", systemImage: "map")
                } description: {
                    Text("Drop CSV files here or use Import CSV in the toolbar.")
                } actions: {
                    Button("Import CSV…") {
                        workspace.isImporterPresented = true
                    }
                }
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

private struct FlightLegTable: View {
    @ObservedObject var workspace: RouteWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Flight Legs")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Table(workspace.legSummaries, selection: $workspace.selectedLegID) {
                TableColumn("Flight") { row in
                    Text(row.flightNumber)
                }
                TableColumn("Callsign") { row in
                    Text(row.callsign)
                }
                TableColumn("Points") { row in
                    Text(row.pointCount.formatted())
                        .monospacedDigit()
                }
                TableColumn("From") { row in
                    Text(row.origin)
                }
                TableColumn("To") { row in
                    Text(row.destination)
                }
                TableColumn("Connection") { row in
                    Label(
                        row.connection,
                        systemImage: row.connects
                            ? "checkmark.circle"
                            : "exclamationmark.triangle"
                    )
                    .foregroundStyle(row.connects ? Color.secondary : Color.red)
                }
            }
        }
        .accessibilityIdentifier("route.legTable")
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
