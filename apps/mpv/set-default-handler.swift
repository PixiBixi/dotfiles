// Usage: swift set-default-handler.swift <app path> <extension>...
// Makes the app the default handler of each extension's UTType, exits 1 if one did not stick.
import AppKit
import UniformTypeIdentifiers

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: set-default-handler.swift <app path> <extension>...\n".data(using: .utf8)!)
    exit(2)
}
let app = URL(fileURLWithPath: args[0]).standardizedFileURL
let types: [(String, UTType)] = args.dropFirst().compactMap { ext in
    guard let type = UTType(filenameExtension: ext) else {
        print("\(ext): no UTType, skipped")
        return nil
    }
    return (ext, type)
}

func handler(_ type: UTType) -> URL? {
    NSWorkspace.shared.urlForApplication(toOpen: type)?.standardizedFileURL
}

func assign(_ todo: [(String, UTType)]) {
    var pending = todo.count
    for (_, type) in todo {
        NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { _ in
            DispatchQueue.main.async { pending -= 1 }
        }
    }
    let deadline = Date().addingTimeInterval(30)
    while pending > 0 && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
}

// macOS asks for a confirmation per type: only touch the ones not already bound to the app,
// so a re-run prompts for nothing. No retry either, it would prompt again after a refusal.
let todo = types.filter { handler($0.1) != app }
assign(todo)
let failed = todo.filter { handler($0.1) != app }

for (ext, type) in failed {
    print("\(ext) (\(type.identifier)): still opened by \(handler(type)?.lastPathComponent ?? "nothing")")
}
exit(failed.isEmpty ? 0 : 1)
