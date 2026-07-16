import SwiftUI

struct RouteInspector: View {
    @ObservedObject var workspace: RouteWorkspace

    var body: some View {
        Form {
            Section("Labels") {
                TextField("Title", text: $workspace.settings.title)
                TextField("Airport Codes", text: $workspace.settings.airportCodes)
                TextField("Airport Names", text: $workspace.settings.airportNames)
                TextField("Route Subtitle", text: $workspace.settings.routeSubtitle)
            }

            Section("Map Content") {
                Toggle("Country Borders", isOn: $workspace.settings.showBorders)
                Toggle("Country Labels", isOn: $workspace.settings.showCountryLabels)
                Toggle("Airport Labels", isOn: $workspace.settings.showAirportLabels)
                Toggle("Flight Metadata", isOn: $workspace.settings.showMetadata)
            }

            Section("Output") {
                integerStepper(
                    "Design Width",
                    value: $workspace.settings.designWidth,
                    range: 320...10_000
                )
                integerStepper(
                    "Design Height",
                    value: $workspace.settings.designHeight,
                    range: 200...10_000
                )
                decimalStepper(
                    "Output Scale",
                    value: $workspace.settings.outputScale,
                    range: 0.1...100,
                    step: 1,
                    suffix: "×"
                )
            }

            Section("Colors") {
                colorPicker("Ocean", keyPath: \.oceanColor)
                colorPicker("Land", keyPath: \.landColor)
                colorPicker("Coastline", keyPath: \.coastlineColor)
                colorPicker("Borders", keyPath: \.borderColor)
                colorPicker("Route", keyPath: \.routeColor)
                colorPicker("Marker", keyPath: \.markerColor)
                colorPicker("Text", keyPath: \.textColor)
            }

            Section("Route") {
                decimalStepper(
                    "Route Width",
                    value: $workspace.settings.routeWidth,
                    range: 0.1...20,
                    step: 0.1,
                    suffix: " pt"
                )
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 280, ideal: 310, max: 380)
        .accessibilityIdentifier("route.inspector")
    }

    private func integerStepper(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent(title) {
                Text(value.wrappedValue.formatted())
                    .monospacedDigit()
            }
        }
    }

    private func decimalStepper(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(title) {
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(1))) + suffix)
                    .monospacedDigit()
            }
        }
    }

    private func colorPicker(
        _ title: String,
        keyPath: WritableKeyPath<WorkspaceRenderSettings, String>
    ) -> some View {
        ColorPicker(
            selection: Binding(
                get: { Color(hexRGB: workspace.settings[keyPath: keyPath]) },
                set: { workspace.settings[keyPath: keyPath] = $0.hexRGB }
            ),
            supportsOpacity: false
        ) {
            LabeledContent(title) {
                Text(workspace.settings[keyPath: keyPath])
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
