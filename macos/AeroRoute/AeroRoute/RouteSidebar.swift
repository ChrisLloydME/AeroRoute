import SwiftUI

struct RouteSidebar: View {
    @ObservedObject var workspace: RouteWorkspace

    var body: some View {
        List(selection: $workspace.selectedLegID) {
            Section("Flight Legs") {
                ForEach(workspace.legs) { leg in
                    FlightLegLabel(leg: leg)
                        .tag(leg.id)
                        .help(leg.source.path)
                }
                .onMove(perform: workspace.moveLegs)
                .onDelete(perform: workspace.removeLegs)
            }
        }
        .navigationTitle("Flight Legs")
        .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 360)
        .overlay {
            if workspace.legs.isEmpty {
                ContentUnavailableView {
                    Label("No Flight Legs", systemImage: "airplane")
                } description: {
                    Text("Import or drop Flightradar24 CSV files in itinerary order.")
                } actions: {
                    Button("Import CSV…") {
                        workspace.isImporterPresented = true
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            workspace.importURLs(urls)
            return urls.contains { $0.pathExtension.lowercased() == "csv" }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                ControlGroup {
                    Button {
                        workspace.isImporterPresented = true
                    } label: {
                        Label("Import CSV", systemImage: "plus")
                    }
                    .help("Import Flightradar24 CSV")

                    Button {
                        workspace.removeSelectedLeg()
                    } label: {
                        Label("Remove Leg", systemImage: "minus")
                    }
                    .disabled(workspace.selectedLegID == nil)
                    .help("Remove selected flight leg")
                }
                .labelStyle(.iconOnly)

                Menu {
                    Button("Move Up", systemImage: "arrow.up") {
                        workspace.moveSelectedLeg(by: -1)
                    }
                    Button("Move Down", systemImage: "arrow.down") {
                        workspace.moveSelectedLeg(by: 1)
                    }
                    Divider()
                    Button("Clear All", systemImage: "trash", role: .destructive) {
                        workspace.clear()
                    }
                    .disabled(workspace.legs.isEmpty)
                } label: {
                    Label("Flight leg actions", systemImage: "ellipsis")
                }
                .fixedSize()

                Spacer()
            }
            .controlSize(.small)
            .padding(8)
            .background(.bar)
        }
        .accessibilityIdentifier("route.sidebar")
    }
}

private struct FlightLegLabel: View {
    let leg: FlightLegItem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(leg.flightNumber)
                    .fontWeight(.medium)
                Text("\(leg.pointCount.formatted()) points · \(leg.callsign.isEmpty ? "no callsign" : leg.callsign)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "airplane")
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
