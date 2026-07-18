//
//  AeroRouteApp.swift
//  AeroRoute
//
//  Created by Christopher Lloyd on 2026.07.15.
//

import SwiftUI

@main
struct AeroRouteApp: App {
    var body: some Scene {
        WindowGroup {
            WorkspaceScene()
        }
#if os(macOS)
        .defaultSize(width: 1_000, height: 700)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AeroRouteCommands()
        }
#endif
    }
}

private struct WorkspaceScene: View {
    @StateObject private var workspace = RouteWorkspace()

    var body: some View {
        ContentView(workspace: workspace)
#if os(macOS)
            .focusedSceneValue(\.routeWorkspace, workspace)
#endif
    }
}

#if os(macOS)
private struct RouteWorkspaceFocusedKey: FocusedValueKey {
    typealias Value = RouteWorkspace
}

private extension FocusedValues {
    var routeWorkspace: RouteWorkspace? {
        get { self[RouteWorkspaceFocusedKey.self] }
        set { self[RouteWorkspaceFocusedKey.self] = newValue }
    }
}

private struct AeroRouteCommands: Commands {
    @FocusedValue(\.routeWorkspace) private var workspace

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Import CSV…") {
                workspace?.isImporterPresented = true
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(workspace == nil)
        }

        CommandMenu("Route") {
            Button("Validate") {
                workspace?.validateNow()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(workspace?.legs.isEmpty != false)

            Divider()

            Button("Export to Files (SVG)…") {
                workspace?.prepareExport()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(workspace?.canExport != true)

            Button("Save to Photos (PNG)") {
                workspace?.preparePhotoExport()
            }
            .disabled(workspace?.canExport != true)
        }
    }
}
#endif
