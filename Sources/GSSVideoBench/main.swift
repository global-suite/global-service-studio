// GSSVideoBench measures heavy video playback on the slowest supported Mac before the media
// layer relies on it (ADR 0008). It is a developer tool: its console output is English only and
// it shares no code with the app. See docs/video-benchmark.md.
import AppKit

// Playback measurement (play, run-all) follows in the next pull request.

let usage = """
    usage:
      GSSVideoBench make-clips <dir> [--seconds N]
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { fail(usage) }
let command = args[0], path = URL(fileURLWithPath: args[1])

/// The positive number after `name`, or `fallback` when the option is absent.
func number(_ name: String, _ fallback: Int) -> Int {
    guard let i = args.firstIndex(of: name) else { return fallback }
    guard i + 1 < args.count, let value = Int(args[i + 1]), value > 0 else { fail("\(name) needs a positive number") }
    return value
}

switch command {
case "make-clips":
    do { try ClipMaker.makeAll(in: path, seconds: number("--seconds", 20)) } catch { fail(error.localizedDescription) }
default:
    fail(usage)
}
