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
                .width(72)
                TableColumn("Callsign") { row in
                    Text(row.callsign)
                }
                .width(78)
                TableColumn("Points") { row in
                    Text(row.pointCount.formatted())
                        .monospacedDigit()
                }
                .width(62)
                TableColumn("From") { row in
                    Text(row.origin)
                }
                .width(48)
                TableColumn("To") { row in
                    Text(row.destination)
                }
                .width(48)
                TableColumn("Connection") { row in
                    Label(
                        row.connection,
                        systemImage: row.connects
                            ? "checkmark.circle"
                            : "exclamationmark.triangle"
                    )
                    .foregroundStyle(row.connects ? Color.secondary : Color.red)
                }
                .width(100)
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
