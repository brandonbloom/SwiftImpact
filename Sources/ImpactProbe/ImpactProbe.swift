import Foundation
import Synchronization

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
///
/// Work done once and shared by several tests, such as a context computed on first use and
/// cached, runs inside at most one test's recording. Record it under an identifier of its own,
/// and add that identifier as a dependency of each test that uses it, whenever the test is found
/// to use it:
///
/// ```swift
/// let shared = ImpactProbe.start(test: "shared/SampleLibrary", declaredIn: #fileID)
/// let library = makeSampleLibrary()
/// shared.stop()
///
/// // While recording a test that uses it:
/// probe.addDependency("shared/SampleLibrary")
/// ```
public final class ImpactProbe: Sendable {
    let test: String
    let fileID: String?
    /// Each instrumented image's counters when the probe started; `nil` when not recording.
    let start: [[UInt64]]?
    /// The recordings the test depends on, and whether the probe has stopped.
    let state = Mutex<(dependencies: [String], stopped: Bool)>(([], false))

    init(test: String, fileID: String?, start: [[UInt64]]?) {
        self.test = test
        self.fileID = fileID
        self.start = start
    }

    /// Starts recording `test`, an identifier the harness chooses and keeps stable from run to
    /// run, declared in the file with `#fileID` `fileID`.
    ///
    /// Pass `nil` for `fileID` if the declaring file isn't known. The test is still recorded, but
    /// code that macros generate in that file isn't, since it has no counters.
    public static func start(test: String, declaredIn fileID: String?) -> ImpactProbe {
        ImpactProbe(test: test, fileID: fileID, start: Session.current?.counters())
    }

    /// Records that the test depends on the recording `recording`, such as of shared work: the
    /// test is impacted whenever that recording is, or doesn't exist. Call it from any thread
    /// before ``stop()``; after, it does nothing.
    public func addDependency(_ recording: String) {
        state.withLock { state in
            if !state.stopped { state.dependencies.append(recording) }
        }
    }

    /// Stops recording and saves what the test ran. Wait for any work the test started first:
    /// what runs after this isn't recorded. Stopping again does nothing.
    public func stop() {
        let dependencies: [String]? = state.withLock { state in
            if state.stopped { return nil }
            state.stopped = true
            return state.dependencies
        }
        guard let dependencies, let start, let session = Session.current else { return }
        session.save(
            RecordingFile(
                test: test, declaredIn: fileID, dependsOn: Array(Set(dependencies)).sorted(),
                images: session.images.map(\.uuid), functions: session.executed(since: start)))
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
            FileHandle.standardError.write(Data("ImpactProbe: not recording: \(problem)\n".utf8))
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

    /// Writes `recording` to the directory under a name of its own, atomically. A recording that
    /// can't be saved only means its test runs next time, so a failure is reported, not thrown.
    func save(_ recording: RecordingFile) {
        let directory = URL(filePath: directory, directoryHint: .isDirectory)
        let name = "\(recording.time)-\(UInt64.random(in: 0...UInt64.max)).json"
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(recording).write(
                to: directory.appending(path: name), options: .atomic)
        } catch {
            FileHandle.standardError.write(
                Data("ImpactProbe: can't save the recording of \(recording.test): \(error)\n".utf8))
        }
    }
}
