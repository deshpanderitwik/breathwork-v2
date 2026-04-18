import SwiftUI

/// SwiftUI form that mirrors the web app's setup view.
/// Same five fields, same units, same total-duration readout.
struct SettingsView: View {
    @Binding var config: SessionConfig
    var onChange: (SessionConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BREATHE")
                .font(.system(size: 11, weight: .medium))
                .kerning(1.0)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            field("Inhale", value: $config.inhaleSec, unit: "sec", step: 1)
            Divider().opacity(0.4)
            field("Exhale", value: $config.exhaleSec, unit: "sec", step: 1)
            Divider().opacity(0.4)
            field("Active phase", value: $config.activeSec, unit: "sec", step: 10)
            Divider().opacity(0.4)
            field("Rest phase", value: $config.restSec, unit: "sec", step: 5)
            Divider().opacity(0.4)
            intField("Rounds", value: $config.rounds, unit: "", step: 1)

            Divider()

            HStack {
                Text("Total · \(config.formattedDuration())")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(width: 260)
        .onChange(of: config) { _, newValue in
            onChange(newValue)
        }
    }

    @ViewBuilder
    private func field(_ label: String, value: Binding<Double>, unit: String, step: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 60)
            Text(unit)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func intField(_ label: String, value: Binding<Int>, unit: String, step: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 60)
            Text(unit)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
