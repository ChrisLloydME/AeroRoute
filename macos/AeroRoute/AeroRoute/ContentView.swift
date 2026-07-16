//
//  ContentView.swift
//  AeroRoute
//
//  Created by Christopher Lloyd on 2026.07.15.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var workspace: RouteWorkspace

    var body: some View {
        NavigationSplitView {
            RouteSidebar(workspace: workspace)
        } detail: {
            RouteDetailView(workspace: workspace)
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $workspace.isInspectorPresented) {
            RouteInspector(workspace: workspace)
        }
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    workspace.isImporterPresented = true
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .help("Import Flightradar24 CSV")
                .keyboardShortcut("o", modifiers: .command)

#if os(macOS)
                ControlGroup {
                    Button {
                        workspace.moveSelectedLeg(by: -1)
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    Button {
                        workspace.moveSelectedLeg(by: 1)
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                }
                .labelStyle(.iconOnly)
#endif

                Button {
                    workspace.validateNow()
                } label: {
                    Label("Validate", systemImage: "checkmark.circle")
                }
                .disabled(workspace.legs.isEmpty)

                Button {
                    workspace.isInspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                }
                .help("Show or hide inspector")

                Button {
                    workspace.prepareExport()
                } label: {
                    Label("Export SVG", systemImage: "square.and.arrow.up")
                }
                .disabled(!workspace.canExport)
                .help("Export deterministic SVG")
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .accessibilityIdentifier("route.export")
            }
        }
        .fileImporter(
            isPresented: $workspace.isImporterPresented,
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(workspace: RouteWorkspace())
            .frame(width: 1_300, height: 820)
    }
}
