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
        .defaultSize(width: 1_440, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentMinSize)
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
            .frame(minWidth: 900, minHeight: 620)
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

            Button("Move Leg Up") {
                workspace?.moveSelectedLeg(by: -1)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(workspace?.selectedLegID == nil)

            Button("Move Leg Down") {
                workspace?.moveSelectedLeg(by: 1)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(workspace?.selectedLegID == nil)

            Divider()

            Button("Export SVG…") {
                workspace?.prepareExport()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(workspace?.canExport != true)
        }
    }
}
#endif
