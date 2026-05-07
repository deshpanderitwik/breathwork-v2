import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Reusable settings form — five rows matching the web app's setup view.
/// Hosts (macOS popover, iOS screen) wrap this with their own chrome.
///
/// Text inputs use a String buffer + parse-on-edit so typing feels live
/// (the `.number` format binding otherwise only commits on focus loss,
/// making multi-digit edits look broken on iOS).
public struct SettingsView: View {
    @Binding var config: SessionConfig

    private enum Field: Hashable {
        case inhale, exhale, active, rest, rounds
    }

    @FocusState private var focused: Field?

    public init(config: Binding<SessionConfig>) {
        self._config = config
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            numberRow("Inhale", unit: "sec", field: .inhale,
                      get: { config.inhaleSec }, set: { config.inhaleSec = $0 })
            Divider().opacity(0.4)
            numberRow("Exhale", unit: "sec", field: .exhale,
                      get: { config.exhaleSec }, set: { config.exhaleSec = $0 })
            Divider().opacity(0.4)
            numberRow("Active phase", unit: "sec", field: .active,
                      get: { config.activeSec }, set: { config.activeSec = $0 })
            Divider().opacity(0.4)
            numberRow("Rest phase", unit: "sec", field: .rest,
                      get: { config.restSec }, set: { config.restSec = $0 })
            Divider().opacity(0.4)
            intRow("Rounds", unit: "", field: .rounds,
                   get: { config.rounds }, set: { config.rounds = $0 })

            #if !os(iOS)
            // macOS menu-bar popover renders Total here; iOS shows it in
            // RootView next to the Start button, so we omit it on iOS.
            Divider()

            HStack {
                Text("Total · \(config.formattedDuration())")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            #endif
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
                .fontWeight(.medium)
            }
        }
        #endif
    }

    @ViewBuilder
    private func numberRow(
        _ label: String, unit: String, field: Field,
        get: @escaping () -> Double, set: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 14))
            Spacer()
            NumberField(
                value: Binding(get: get, set: set),
                focused: $focused,
                field: field
            )
            .frame(width: 72)
            Text(unit)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func intRow(
        _ label: String, unit: String, field: Field,
        get: @escaping () -> Int, set: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 14))
            Spacer()
            NumberField(
                value: Binding(get: { Double(get()) }, set: { set(Int($0)) }),
                focused: $focused,
                field: field
            )
            .frame(width: 72)
            Text(unit)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// TextField wrapper with live string-parsing — every keystroke updates
/// the bound Double. Empty string is tolerated (value left unchanged).
private struct NumberField<F: Hashable>: View {
    @Binding var value: Double
    var focused: FocusState<F?>.Binding
    let field: F

    @State private var text: String = ""

    var body: some View {
        #if os(iOS)
        // UIKit-backed so we can selectAll() on focus — tap the field and
        // the whole value is selected, so typing replaces it cleanly.
        SelectAllNumberTextField(text: $text)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .onAppear { text = format(value) }
            .onChange(of: value) { _, new in
                if parse(text) != new { text = format(new) }
            }
            .onChange(of: text) { _, new in
                if let parsed = parse(new), parsed > 0 {
                    value = parsed
                }
            }
        #else
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .focused(focused, equals: field)
            .onAppear { text = format(value) }
            .onChange(of: value) { _, new in
                if parse(text) != new { text = format(new) }
            }
            .onChange(of: text) { _, new in
                if let parsed = parse(new), parsed > 0 {
                    value = parsed
                }
            }
        #endif
    }

    private func format(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        return String(v)
    }

    private func parse(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return Double(trimmed)
    }
}

#if os(iOS)
/// UITextField wrapper that selects all text on focus. Tap the field and
/// the whole existing value is highlighted, so typing replaces it —
/// matches the behavior users expect from iOS settings-style inputs.
private struct SelectAllNumberTextField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.textAlignment = .center
        tf.font = .systemFont(ofSize: 15)
        tf.textColor = .white
        tf.tintColor = .white
        tf.delegate = context.coordinator
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllNumberTextField
        init(_ parent: SelectAllNumberTextField) { self.parent = parent }

        @objc func editingChanged(_ tf: UITextField) {
            parent.text = tf.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            // Dispatch so selection sticks — iOS otherwise clears it on
            // the same run loop as the tap.
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }
    }
}
#endif
