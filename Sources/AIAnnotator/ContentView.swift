import AnnotatorCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @ViewState private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                OllamaBanner()
                if let session = app.session {
                    ReviewView(session: session).id(session.id)
                } else {
                    HomeView(dropTargeted: dropTargeted)
                }
            }
            .background(Theme.canvas)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                loadURLs(providers) { app.open($0) }
                return true
            }
        }
        .tint(Theme.brand)
        .sheet(item: $app.pending) { run in
            RunSheet(run: run).environmentObject(app).tint(Theme.brand)
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
            banner("Ollama isn't running", detail: "Open the Ollama app, then retry.", command: nil)
        case .modelMissing(let model):
            banner("\(model) isn't installed", detail: "Install it, or pick another model in Settings.",
                   command: "ollama pull \(model)")
        }
    }

    private func banner(_ title: String, detail: String, command: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if let command {
                Text(command)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            Spacer()
            Button("Retry") { Task { await app.refreshOllama() } }.buttonStyle(SoftButtonStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.25)))
        .padding(.horizontal, 16).padding(.top, 10)
    }
}

struct LibrarySidebar: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                BrandMark(size: 26)
                Text("AI Annotator").font(Theme.display(15))
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)

            Button { app.openPanel() } label: {
                Label("New reading", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 14)

            SidebarItem(symbol: "house", title: "Home", selected: app.session == nil) { app.newReading() }
                .padding(.horizontal, 8).padding(.top, 14)

            SectionLabel("Library").padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 6)

            if app.library.isEmpty {
                Text("Readings you process show up here.")
                    .font(.callout).foregroundStyle(.tertiary)
                    .padding(.horizontal, 18)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(app.library) { item in
                            SidebarItem(symbol: item.mode.symbol, title: item.title,
                                        subtitle: item.createdAt.formatted(.relative(presentation: .named)),
                                        selected: app.session?.id == item.id) { app.openItem(item.id) }
                                .contextMenu {
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([app.libraryStore.pdfURL(for: item.id)])
                                    }
                                    Button("Delete", role: .destructive) { app.delete(item) }
                                }
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SidebarItem: View {
    let symbol: String
    let title: String
    var subtitle: String?
    let selected: Bool
    let action: () -> Void
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? Theme.brand : .secondary)
                    .frame(width: 26, height: 26)
                    .background(selected ? Theme.brand.opacity(0.14) : Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Theme.brand.opacity(0.1) : hover ? Color.primary.opacity(0.05) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    let dropTargeted: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                VStack(spacing: 14) {
                    BrandMark(size: 72)
                        .shadow(color: Theme.brand.opacity(0.35), radius: 22, y: 10)
                    Text("Turn any reading into study material")
                        .font(Theme.display(30))
                        .multilineTextAlignment(.center)
                    Text("Drop in a PDF or photos of pages. Notes and highlights are made right on your Mac, and nothing leaves it.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 470)
                }
                .padding(.top, 36)

                dropCard

                HStack(spacing: 12) {
                    FeatureTile(symbol: "note.text", title: "Notes your way", detail: "Cornell, outline, key terms or Q&A")
                    FeatureTile(symbol: "highlighter", title: "Focused highlights", detail: "Only what matters, color-coded")
                    FeatureTile(symbol: "lock.fill", title: "Private", detail: "Runs locally with Ollama")
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620)

                if !app.library.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Recent")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                            ForEach(app.library.prefix(6)) { item in
                                RecentCard(item: item) { app.openItem(item.id) }
                            }
                        }
                    }
                    .frame(maxWidth: 620)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    private var dropCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: -8) {
                icon("doc.richtext", tint: Theme.brand)
                icon("photo.on.rectangle", tint: Theme.gold)
            }
            Text(dropTargeted ? "Drop to start" : "Drop files here")
                .font(Theme.display(17))
            Button { app.openPanel() } label: { Label("Choose files", systemImage: "folder") }
                .buttonStyle(PrimaryButtonStyle(large: true))
            Text("PDF, JPG, PNG or HEIC · about 1–20 pages · ⌘O")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 620)
        .padding(.vertical, 34)
        .card(22)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .foregroundStyle(Theme.brand)
                .opacity(dropTargeted ? 1 : 0)
        }
        .background {
            RoundedRectangle(cornerRadius: 22).fill(Theme.brand.opacity(0.18)).blur(radius: 30)
                .opacity(dropTargeted ? 1 : 0)
        }
        .scaleEffect(dropTargeted ? 1.015 : 1)
        .animation(.spring(duration: 0.3), value: dropTargeted)
    }

    private func icon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 46, height: 46)
            .background(Theme.card, in: Circle())
            .overlay(Circle().strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

struct FeatureTile: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.brand)
            Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .card(14, shadow: false)
    }
}

struct RecentCard: View {
    let item: ReadingItem
    let action: () -> Void
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: item.mode.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 32, height: 32)
                    .background(Theme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("\(item.mode.label) · \(item.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .card(12, shadow: hover)
            .offset(y: hover ? -1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}
