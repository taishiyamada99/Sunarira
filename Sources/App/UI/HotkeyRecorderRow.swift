import AppKit
import SwiftUI

struct HotkeyRecorderRow: View {
    let title: String
    let hotkey: Hotkey
    let recordingLabel: String
    let onChange: (Hotkey) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(isRecording ? recordingLabel : hotkey.displayString) {
                startRecording()
            }
            .buttonStyle(.bordered)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }

            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let shortcut = Hotkey(
                keyCode: UInt32(event.keyCode),
                modifiers: Hotkey.modifiers(from: event.modifierFlags)
            )

            if shortcut.isValid {
                onChange(shortcut)
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
