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
                    workspace.prepareExport()
                } label: {
                    Label("Export SVG", systemImage: "square.and.arrow.up")
                }
                .disabled(!workspace.canExport)
                .help("Export deterministic SVG")
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .accessibilityIdentifier("route.export")

                Button {
                    workspace.isInspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Show or hide inspector")
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(workspace: RouteWorkspace())
            .frame(width: 1_300, height: 820)
    }
}
