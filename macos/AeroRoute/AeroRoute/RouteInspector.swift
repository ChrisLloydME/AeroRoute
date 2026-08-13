import SwiftUI

struct RouteInspector: View {
    @ObservedObject var workspace: RouteWorkspace

    var body: some View {
        Form {
            Section("Labels") {
                TextField("Title", text: $workspace.settings.title)
                TextField("Route Subtitle", text: $workspace.settings.routeSubtitle)
            }

            Section("Map Content") {
                Toggle("Country Borders", isOn: $workspace.settings.showBorders)
                Toggle("Country Labels", isOn: $workspace.settings.showCountryLabels)
                Toggle("Airport Labels", isOn: $workspace.settings.showAirportLabels)
                Toggle("Flight Metadata", isOn: $workspace.settings.showMetadata)
                Toggle("Fit Map to Route", isOn: $workspace.settings.fitMapToRoute)
                    .accessibilityIdentifier("route.fitMapToRoute")
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
                    suffix: "pt"
                )
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("route.inspector")
    }

    private func integerStepper(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                Spacer()
                TextField(
                    title,
                    value: clamped(value, to: range),
                    format: .number.grouping(.automatic)
                )
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 84)
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
            HStack {
                Text(title)
                Spacer()
                HStack(spacing: 4) {
                    TextField(
                        title,
                        value: clamped(value, to: range),
                        format: .number.precision(.fractionLength(1))
                    )
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 60)
                    Text(suffix)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(width: 84, alignment: .trailing)
            }
        }
    }

    private func clamped<T: Comparable>(
        _ value: Binding<T>,
        to range: ClosedRange<T>
    ) -> Binding<T> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    private func colorPicker(
        _ title: String,
        keyPath: WritableKeyPath<WorkspaceRenderSettings, String>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            Text(workspace.settings[keyPath: keyPath])
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            ColorPicker(
                title,
                selection: Binding(
                    get: { Color(hexRGB: workspace.settings[keyPath: keyPath]) },
                    set: { workspace.settings[keyPath: keyPath] = $0.hexRGB }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }
}
