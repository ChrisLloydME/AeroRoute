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
        .overlay {
            if workspace.legs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "airplane")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No Flight Legs")
                        .font(.headline)
                    Text("Import or drop CSV files in itinerary order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
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
