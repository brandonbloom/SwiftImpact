import Darwin

/// A test being recorded: what it runs, from start to stop, saved for `ImpactAnalysis`.
///
/// ```swift
/// let probe = ImpactProbe.start(test: "MyModule/ParserTests/parsesNumbers", declaredIn: #fileID)
/// runTheTest()
/// probe.stop()
/// ```
///
/// A probe records only in a process built with `ImpactAnalysis.buildArguments` and launched with
/// `ImpactAnalysis.environment(for:)`. Anywhere else, it does nothing.
///
/// Probes may overlap. Each records everything that runs in its process while it's started,
/// including other tests' work.
public struct ImpactProbe: Sendable {
    let test: String
    let fileID: String
    /// Each instrumented image's counters when the probe started; `nil` when not recording.
    let start: [[UInt64]]?

    /// Starts recording `test`, an identifier the harness chooses and keeps stable from run to
    /// run, declared in the file with `#fileID` `fileID`.
    public static func start(test: String, declaredIn fileID: String) -> ImpactProbe {
        ImpactProbe(test: test, fileID: fileID, start: Session.current?.counters())
    }

    /// Stops recording and saves what the test ran. Wait for any work the test started first:
    /// what runs after this isn't recorded.
    public func stop() {
        guard let start, let session = Session.current else { return }
        session.save(
            RecordingFile(
                test: test, declaredIn: fileID, images: session.images.map(\.uuid),
                functions: session.executed(since: start)))
    }
}

/// The process's instrumented images and where to save recordings, found on first use.
struct Session: Sendable {
    /// The environment variable naming the directory to save recordings in. `ImpactAnalysis`
    /// sets it.
    static let directoryVariable = "SWIFTIMPACT_RECORDINGS"

    let images: [Image]
    let directory: String

    /// The session, or `nil` if this process isn't set up to record.
    static let current: Session? = {
        guard let directory = getenv(directoryVariable).map({ String(cString: $0) }) else {
            return nil
        }
        switch Image.loaded() {
        case .success(let images):
            return Session(images: images, directory: directory)
        case .failure(let problem):
            fputs("ImpactProbe: not recording: \(problem)\n", stderr)
            return nil
        }
    }()

    /// A copy of every image's counters.
    func counters() -> [[UInt64]] {
        images.map { Array($0.counters.bindMemory(to: UInt64.self)) }
    }

    /// The name hashes of the functions whose counters moved since `start`, a copy from
    /// ``counters()``.
    func executed(since start: [[UInt64]]) -> [UInt64] {
        var executed: [UInt64] = []
        for (image, before) in zip(images, start) {
            image.forEachFunction { nameRef, first, counters in
                if counters.indices.contains(where: { counters[$0] != before[first + $0] }) {
                    executed.append(nameRef)
                }
            }
        }
        return executed
    }

    /// Writes `recording` to the directory under a name of its own, atomically.
    func save(_ recording: RecordingFile) {
        var path = ""
        for component in directory.split(separator: "/") {
            path += "/\(component)"
            mkdir(path, 0o755)
        }
        let name = "\(recording.time)-\(UInt64.random(in: 0...UInt64.max)).json"
        let temporary = "\(directory)/.\(name)"
        let fd = open(temporary, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { return }
        let bytes = Array(recording.json.utf8)
        let written = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        close(fd)
        if written == bytes.count {
            rename(temporary, "\(directory)/\(name)")
        } else {
            unlink(temporary)
        }
    }
}
