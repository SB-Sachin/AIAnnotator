import AnnotatorCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @ViewState private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            VStack(spacing: 0) {
                OllamaBanner()
                if let session = app.session {
                    ReviewView(session: session).id(session.id)
                } else {
                    HomeView(dropTargeted: dropTargeted)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                loadURLs(providers) { app.open($0) }
                return true
            }
        }
        .sheet(item: $app.pending) { run in
            RunSheet(run: run).environmentObject(app)
        }
    }
}

func loadURLs(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    for provider in providers {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        MainActor.assumeIsolated { completion(urls) }
    }
}

struct OllamaBanner: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        switch app.status {
        case .ok, .checking:
            EmptyView()
        case .notRunning:
            banner("Ollama isn't running. Open the Ollama app, then click Retry.", command: nil)
        case .modelMissing(let model):
            banner("The model \(model) isn't installed. Install it, or pick another model in Settings.",
                   command: "ollama pull \(model)")
        }
    }

    private func banner(_ text: String, command: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text)
            if let command {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
            Spacer()
            Button("Retry") { Task { await app.refreshOllama() } }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color.orange.opacity(0.12))
    }
}

struct LibrarySidebar: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        List(selection: $app.selection) {
            Section("Library") {
                ForEach(app.library) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).lineLimit(1)
                        Text("\(item.mode.label) · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(item.id)
                    .contextMenu {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([app.libraryStore.pdfURL(for: item.id)])
                        }
                        Button("Delete", role: .destructive) { app.delete(item) }
                    }
                }
            }
        }
        .onChange(of: app.selection) { _, id in app.openItem(id) }
        .safeAreaInset(edge: .bottom) {
            Button { app.newReading() } label: {
                Label("New Reading", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .overlay {
            if app.library.isEmpty {
                Text("Readings you process show up here.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding()
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    let dropTargeted: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Drop a reading here").font(.title.weight(.semibold))
            Text("A PDF, or photos of textbook pages. Everything runs on your Mac with Ollama.")
                .foregroundStyle(.secondary)
            Button("Choose Files…") { app.openPanel() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
                .background(dropTargeted ? Color.accentColor.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 16))
                .padding(24)
        }
    }
}
