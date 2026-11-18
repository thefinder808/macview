import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Draws a vector image (SVG) in a throwaway child process first, so a file
/// that makes AppKit's renderer allocate gigabytes kills the child, not the app.
///
/// Why a process and not a check of the file: the cost of an SVG filter or mask
/// is the affected element's bounding box × region in viewBox units, transforms
/// included, and it is paid on *every* draw whatever the output size — a 200px
/// thumbnail costs the same as the canvas. A `transform="scale(100)"`, a huge
/// `<rect>`, a CSS `filter:`, or a file declared as UTF-7 all hide that cost
/// from any scan of the text, so the only reliable answer is to try the draw
/// somewhere it can fail safely. See docs/ARCHITECTURE.md.
///
/// The child is this same executable, started with `flag`. It draws the
/// thumbnail, writes it to stdout as PNG, and exits; a watchdog thread ends it
/// if it passes `memoryLimit` or `timeLimit`. A thumbnail that comes back means
/// the file is safe to draw in-process, because the cost doesn't depend on size.
enum VectorProbe {
    static let flag = "--probe-vector"
    /// The child's whole footprint. A file that passes costs the app at most
    /// about this much on top of its baseline, keeping the app under ~1 GB.
    static let memoryLimit: UInt64 = 512 * 1_048_576
    static let timeLimit: TimeInterval = 5

    // MARK: Parent side

    /// The file's thumbnail, drawn in a child process. Nil if the file can't be
    /// drawn within the limits (or at all).
    static func thumbnail(for url: URL, maxPixel: CGFloat) -> CGImage? {
        // Don't pay for a known-bad file again each time its cell scrolls into view.
        if verdict(for: url) == false { return nil }
        let image = runChild(url: url, maxPixel: maxPixel)
        remember(url, safe: image != nil)
        return image
    }

    /// True if the file drew within the limits. Probes it if nobody has yet.
    /// A tiny probe is enough: the cost measured does not follow output size
    /// or zoom (a file at 501 MB here peaked at 521 MB in the canvas from 18%
    /// to 4000%, rotated or not — macOS 27.2; older systems keep a zoom cap).
    static func isSafe(_ url: URL) -> Bool {
        if let known = verdict(for: url) { return known }
        return thumbnail(for: url, maxPixel: 64) != nil
    }

    /// True only if the file was probed and failed — for the canvas message.
    static func wasRefused(_ url: URL) -> Bool { verdict(for: url) == false }

    private static func runChild(url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = [flag, url.path, String(Int(maxPixel))]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // Read to EOF before waiting, or a full pipe would block the child.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // Verdicts, keyed by URL and remembered with the file's modification date
    // so an edited file is probed again.
    private static let lock = NSLock()
    private static var verdicts: [URL: (modified: Date?, safe: Bool)] = [:]

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func remember(_ url: URL, safe: Bool) {
        let date = modified(url)
        lock.lock(); defer { lock.unlock() }
        verdicts[url] = (date, safe)
    }

    private static func verdict(for url: URL) -> Bool? {
        let date = modified(url)
        lock.lock(); defer { lock.unlock() }
        guard let entry = verdicts[url], entry.modified == date else { return nil }
        return entry.safe
    }

    // MARK: Child side

    /// Call first thing in `main`. Returns immediately in a normal launch; in a
    /// probe launch it draws, writes the PNG, and exits without returning.
    static func runChildIfRequested() {
        let args = CommandLine.arguments
        guard args.count == 4, args[1] == flag, let maxPixel = Double(args[3]) else { return }

        let start = Date()
        Thread.detachNewThread {
            while true {
                if footprint() > memoryLimit { _exit(9) }
                if Date().timeIntervalSince(start) > timeLimit { _exit(8) }
                usleep(5_000)
            }
        }

        guard let image = NSImage(contentsOf: URL(fileURLWithPath: args[2])) else { exit(1) }
        image.clampVectorSize()   // draw what the canvas would draw
        let data = NSMutableData()
        guard let cg = image.rasterized(maxPixel: CGFloat(maxPixel)),
              let destination = CGImageDestinationCreateWithData(
                  data, UTType.png.identifier as CFString, 1, nil)
        else { exit(1) }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { exit(1) }
        FileHandle.standardOutput.write(data as Data)
        exit(0)
    }

    /// This process's physical footprint — the number Activity Monitor shows.
    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
