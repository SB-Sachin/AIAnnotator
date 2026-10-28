import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct AIAnnotatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup("AI Annotator") {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Reading") { app.newReading() }.keyboardShortcut("n")
                Button("Open…") { app.openPanel() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { app.session?.save() }
                    .keyboardShortcut("s")
                    .disabled(app.session == nil)
                Divider()
                Button("Export Annotated PDF…") { app.session?.exportAnnotatedPDF() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(app.session?.document == nil)
                Button("Export Notes as Markdown…") { app.session?.exportNotesMarkdown() }
                    .disabled(app.session?.notes.isEmpty ?? true)
                Button("Export Notes as PDF…") { app.session?.exportNotesPDF() }
                    .disabled(app.session?.notes.isEmpty ?? true)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(app)
                .tint(Theme.brand)
        }
    }
}
