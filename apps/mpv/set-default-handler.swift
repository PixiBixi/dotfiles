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

// Second pass: a type can fail right after lsregister, while the bundle is still being indexed.
assign(types)
var failed = types.filter { handler($0.1) != app }
if !failed.isEmpty {
    Thread.sleep(forTimeInterval: 1)
    assign(failed)
    failed = types.filter { handler($0.1) != app }
}

for (ext, type) in failed {
    print("\(ext) (\(type.identifier)): still opened by \(handler(type)?.lastPathComponent ?? "nothing")")
}
exit(failed.isEmpty ? 0 : 1)
