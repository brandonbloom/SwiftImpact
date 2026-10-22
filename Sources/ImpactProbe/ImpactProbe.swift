import Foundation

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
/// and name that identifier in `dependsOn` when starting each test that uses it:
///
/// ```swift
/// let shared = ImpactProbe.start(test: "shared/SampleLibrary", declaredIn: #fileID)
/// let library = makeSampleLibrary()
/// shared.stop()
///
/// let probe = ImpactProbe.start(
///     test: "CardView/iPhone", declaredIn: "MyApp/CardView.swift",
///     dependsOn: ["shared/SampleLibrary"])
/// ```
public struct ImpactProbe: Sendable {
    let test: String
    let fileID: String?
    let dependencies: [String]
    /// Each instrumented image's counters when the probe started; `nil` when not recording.
    let start: [[UInt64]]?

    /// Starts recording `test`, an identifier the harness chooses and keeps stable from run to
    /// run, declared in the file with `#fileID` `fileID`.
    ///
    /// Pass `nil` for `fileID` if the declaring file isn't known. The test is still recorded, but
    /// code that macros generate in that file isn't, since it has no counters.
    ///
    /// `dependsOn` names other recordings the test depends on, such as of shared work. The test is
    /// impacted whenever one of them is, or has no recording.
    public static func start(
        test: String, declaredIn fileID: String?, dependsOn dependencies: [String] = []
    ) -> ImpactProbe {
        ImpactProbe(
            test: test, fileID: fileID, dependencies: dependencies,
            start: Session.current?.counters())
    }

    /// Stops recording and saves what the test ran. Wait for any work the test started first:
    /// what runs after this isn't recorded.
    public func stop() {
        guard let start, let session = Session.current else { return }
        session.save(
            RecordingFile(
                test: test, declaredIn: fileID, dependsOn: dependencies,
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
