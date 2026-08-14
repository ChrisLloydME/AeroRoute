import SwiftUI

struct RouteSidebar: View {
    @ObservedObject var workspace: RouteWorkspace

    var body: some View {
        List(selection: $workspace.selectedLegID) {
            Section("Files") {
                ForEach(workspace.legs) { leg in
                    ImportedFileLabel(leg: leg)
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
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No Files")
                        .font(.headline)
                    Text("Import or drop CSV files in display order.")
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
                        Label("Remove File", systemImage: "minus")
                    }
                    .disabled(workspace.selectedLegID == nil)
                    .help("Remove selected file")
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

private struct ImportedFileLabel: View {
    let leg: FlightLegItem

    var body: some View {
        Label {
            Text(leg.source.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: "doc.text")
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
