import ResonanceCore
import SwiftUI

/// The whole UI: one switch, the tuning, the status, and any engine error. Audio plays on whatever output macOS
/// uses, so there is no device picker.
struct MenuBarView: View {
    @EnvironmentObject var model: EngineViewModel
    @EnvironmentObject var openAtLogin: OpenAtLoginModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(model.isEnabled && model.errorMessage == nil ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resonance").font(.headline)
                    Text(model.statusText).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = model.notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("Tune:")
                Picker("", selection: $model.pitchMode) {
                    ForEach(PitchMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
            }

            Divider()

            Toggle("Open at login", isOn: Binding(get: { openAtLogin.isOn }, set: { openAtLogin.set($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
            if let error = openAtLogin.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Spacer()
                Button("Quit") {
                    model.shutdown()
                    NSApp.terminate(nil)
                }
                .font(.caption)
            }
        }
        .padding()
        .frame(width: 280)
        // The menu window may be kept between openings, so read the login item again each time it comes up.
        .onAppear { openAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            openAtLogin.refresh()
        }
    }
}
