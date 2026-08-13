//
//  ContentView.swift
//  AeroRoute
//
//  Created by Christopher Lloyd on 2026.07.15.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @ObservedObject var workspace: RouteWorkspace

    var body: some View {
        workspaceView
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    workspace.validateNow()
                } label: {
                    Label("Validate", systemImage: "checkmark.circle")
                }
                .disabled(workspace.legs.isEmpty)

                Button {
                    workspace.matchAirportsFromCSV()
                } label: {
                    Label(
                        workspace.isMatchingAirports ? "Matching Airports…" : "Match Airports",
                        systemImage: "rectangle.and.pencil.and.ellipsis"
                    )
                }
                .disabled(
                    workspace.legs.isEmpty
                        || workspace.isImporting
                        || workspace.isMatchingAirports
                )
                .help("Match route airports automatically from the imported CSV tracks")
                .accessibilityIdentifier("route.matchAirports")

                Menu {
                    Button {
                        workspace.prepareExport()
                    } label: {
                        Label("Export to Files (SVG)", systemImage: "folder")
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                    Button {
                        workspace.preparePhotoExport()
                    } label: {
                        Label("Save to Photos (PNG)", systemImage: "photo")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(!workspace.canExport)
                .help("Export SVG to Files or PNG to Photos")
                .accessibilityIdentifier("route.export")

                Button {
                    workspace.isInspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Show or hide inspector")
            }
        }
        .csvFileImporter(workspace: workspace)
        .fileExporter(
            isPresented: $workspace.isExporterPresented,
            document: workspace.exportDocument,
            contentType: .aeroRouteSVG,
            defaultFilename: workspace.suggestedFilename,
            onCompletion: workspace.handleExport
        )
        .alert(workspace.alertTitle, isPresented: $workspace.isAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(workspace.alertMessage)
        }
        .onChange(of: workspace.settings) {
            workspace.scheduleRender()
        }
        .task {
            workspace.loadCommandLineArgumentsIfNeeded()
        }
    }

    @ViewBuilder
    private var workspaceView: some View {
#if os(macOS)
        NavigationSplitView(columnVisibility: .constant(.all)) {
            RouteSidebar(workspace: workspace)
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            RouteDetailView(workspace: workspace)
                .inspector(isPresented: $workspace.isInspectorPresented) {
                    RouteInspector(workspace: workspace)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 340)
                }
        }
        .navigationSplitViewStyle(.balanced)
#else
        NavigationSplitView {
            RouteSidebar(workspace: workspace)
        } detail: {
            RouteDetailView(workspace: workspace)
                .inspector(isPresented: $workspace.isInspectorPresented) {
                    RouteInspector(workspace: workspace)
                }
        }
        .navigationSplitViewStyle(.balanced)
#endif
    }
}

private extension View {
    @ViewBuilder
    func csvFileImporter(workspace: RouteWorkspace) -> some View {
#if os(macOS)
        modifier(MacOSCSVFileImporter(workspace: workspace))
#else
        fileImporter(
            isPresented: Binding(
                get: { workspace.isImporterPresented },
                set: { workspace.isImporterPresented = $0 }
            ),
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                workspace.importURLs(urls)
            case let .failure(error):
                workspace.presentAlert(
                    title: "Import failed",
                    message: error.localizedDescription
                )
            }
        }
#endif
    }
}

#if os(macOS)
private struct MacOSCSVFileImporter: ViewModifier {
    @ObservedObject var workspace: RouteWorkspace
    @State private var openPanel: NSOpenPanel?

    func body(content: Content) -> some View {
        content
            .onChange(of: workspace.isImporterPresented) { _, isPresented in
                guard isPresented else { return }
                presentOpenPanel()
            }
    }

    @MainActor
    private func presentOpenPanel() {
        guard openPanel == nil else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        openPanel = panel

        panel.begin { response in
            defer {
                openPanel = nil
                workspace.isImporterPresented = false
            }
            guard response == .OK else { return }
            workspace.importURLs(panel.urls)
        }
    }
}
#endif

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(workspace: RouteWorkspace())
            .frame(width: 1_300, height: 820)
    }
}
