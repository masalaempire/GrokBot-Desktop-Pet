import Foundation

enum TaskStep: String, Decodable {
    case working, reading, searching, editing, testing, building, command, tool, approval, input, done, stopped

    var title: String {
        switch self {
        case .working: "Working…"
        case .reading: "Reading files…"
        case .searching: "Searching files…"
        case .editing: "Editing files…"
        case .testing: "Running tests…"
        case .building: "Building…"
        case .command: "Running a command…"
        case .tool: "Using a tool…"
        case .approval: "Approval requested"
        case .input: "Answer in ChatGPT"
        case .done: "Done"
        case .stopped: "Stopped"
        }
    }

    var isFinished: Bool { self == .done || self == .stopped }
    var needsUserAction: Bool { self == .approval || self == .input }
}

struct TaskActivity: Equatable {
    let step: TaskStep
    let otherActiveTasks: Int
}

@MainActor
final class TaskActivityMonitor: NSObject {
    private struct Snapshot: Decodable {
        let version: Int
        let display: TaskStep
        let updatedAt: TimeInterval
    }

    private let bookmarkKey = "taskActivityBookmark"
    private let defaults: UserDefaults
    private let onChange: (TaskActivity?) -> Void
    private var folder: URL?
    private var hasScope = false
    private var timer: Timer?

    private(set) var current: TaskActivity?
    var isConnected: Bool { folder != nil }

    init(defaults: UserDefaults, onChange: @escaping (TaskActivity?) -> Void) {
        self.defaults = defaults
        self.onChange = onChange
    }

    func restore() {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { return }

        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            try beginReading(url, saveBookmark: stale)
        } catch {
            disconnect()
        }
    }

    func connect(to url: URL) throws {
        try beginReading(url, saveBookmark: true)
    }

    func disconnect() {
        timer?.invalidate()
        timer = nil
        if hasScope { folder?.stopAccessingSecurityScopedResource() }
        folder = nil
        hasScope = false
        defaults.removeObject(forKey: bookmarkKey)
        publish(nil)
    }

    private func beginReading(_ url: URL, saveBookmark: Bool) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let marker = url.appendingPathComponent("lumo-activity.json")
            guard FileManager.default.isReadableFile(atPath: marker.path) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            if saveBookmark {
                let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
                defaults.set(bookmark, forKey: bookmarkKey)
            }
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }

        if hasScope { folder?.stopAccessingSecurityScopedResource() }
        timer?.invalidate()
        folder = url
        hasScope = scoped
        let timer = Timer(timeInterval: 0.6, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    @objc private func refresh() {
        guard let folder else { return }
        publish(Self.activity(in: folder))
    }

    private func publish(_ next: TaskActivity?) {
        guard current != next else { return }
        current = next
        onChange(next)
    }

    static func activity(in folder: URL, now: TimeInterval = Date().timeIntervalSince1970) -> TaskActivity? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
        )) ?? []
        let decoder = JSONDecoder()
        let recent = files.compactMap { file -> Snapshot? in
            let name = file.lastPathComponent
            guard name.hasPrefix("lumo-"), name.count == 42, file.pathExtension == "json",
                  let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= 16_384,
                  let modified = values.contentModificationDate,
                  now - modified.timeIntervalSince1970 <= 3_600,
                  let data = try? Data(contentsOf: file),
                  let snapshot = try? decoder.decode(Snapshot.self, from: data),
                  snapshot.version == 1 else { return nil }
            let age = now - snapshot.updatedAt
            return age >= -5 && age <= (snapshot.display.isFinished ? 8 : 3_600) ? snapshot : nil
        }
        let active = recent.filter { !$0.display.isFinished }
        let selected = active.filter { $0.display.needsUserAction }.max { $0.updatedAt < $1.updatedAt }
            ?? active.max { $0.updatedAt < $1.updatedAt }
            ?? recent.max { $0.updatedAt < $1.updatedAt }
        guard let selected else { return nil }
        return TaskActivity(
            step: selected.display,
            otherActiveTasks: max(0, active.count - 1)
        )
    }
}
