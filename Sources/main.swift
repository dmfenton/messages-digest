// messages-digest: read the last N hours of Apple Messages into a private JSON file.
//
// This is the ONLY component that needs Full Disk Access. It opens chat.db read-only,
// never writes to it, never sends anything, and makes no network calls.
// Everything downstream (Claude, scripts) reads the JSON file it writes.

import Foundation
import SQLite3

// MARK: - Configuration

struct Options {
    var hours: Double = 3
    var output: URL = Options.defaultOutput

    static let defaultOutput = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MessagesDigest/latest.json")

    static func parse(_ args: [String]) -> Options {
        var options = Options()
        var iterator = args.dropFirst().makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--hours":
                if let value = iterator.next().flatMap(Double.init), value > 0 { options.hours = value }
            case "--output":
                if let value = iterator.next() { options.output = URL(fileURLWithPath: value) }
            default:
                break  // `open` and launchd can add their own arguments; ignore them.
            }
        }
        return options
    }
}

let chatDatabase = FileManager.default
    .homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Messages/chat.db")

// Apple stores message dates as nanoseconds since 2001-01-01 UTC.
let appleEpoch = Date(timeIntervalSinceReferenceDate: 0)

// MARK: - Output model

struct Message: Encodable {
    let id: String
    let at: Date
    let fromMe: Bool
    let sender: String?       // phone number or email; nil for your own messages
    let chat: String?         // chat identifier (number, email, or group id)
    let chatName: String?     // group name, if the chat has one
    let text: String?
    let hasAttachments: Bool
}

struct Snapshot: Encodable {
    let status: String        // "ok" or an error code
    let detail: String?
    let generatedAt: Date
    let since: Date?
    let hours: Double
    let messageCount: Int
    let messages: [Message]
}

// MARK: - Reading chat.db

enum ExportError: Error {
    case needsFullDiskAccess(String)
    case database(String)

    var code: String {
        switch self {
        case .needsFullDiskAccess: return "needs_full_disk_access"
        case .database: return "database_error"
        }
    }

    var detail: String {
        switch self {
        case .needsFullDiskAccess(let message), .database(let message): return message
        }
    }
}

func openReadOnly(_ url: URL) throws -> OpaquePointer {
    var db: OpaquePointer?
    let result = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
    guard result == SQLITE_OK, let db else {
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
        sqlite3_close(db)
        // "authorization denied" / SQLITE_AUTH / SQLITE_CANTOPEN all mean TCC said no.
        throw ExportError.needsFullDiskAccess("\(url.path): \(message)")
    }
    sqlite3_exec(db, "PRAGMA query_only = ON;", nil, nil, nil)
    return db
}

let query = """
    SELECT m.guid, m.date, m.is_from_me, m.text, m.attributedBody,
           m.cache_has_attachments, h.id, c.chat_identifier, c.display_name
    FROM message m
    LEFT JOIN handle h ON h.ROWID = m.handle_id
    LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
    LEFT JOIN chat c ON c.ROWID = cmj.chat_id
    WHERE m.date >= ?
      AND m.associated_message_type = 0   -- skip tapbacks/reactions
      AND m.item_type = 0                 -- skip group renames, joins, etc.
    ORDER BY m.date ASC
    """

func readMessages(since: Date) throws -> [Message] {
    let db = try openReadOnly(chatDatabase)
    defer { sqlite3_close(db) }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
        let message = String(cString: sqlite3_errmsg(db))
        if message.contains("authorization denied") {
            throw ExportError.needsFullDiskAccess("\(chatDatabase.path): \(message)")
        }
        throw ExportError.database("\(chatDatabase.path): \(message)")
    }
    defer { sqlite3_finalize(statement) }

    let sinceNanos = Int64(since.timeIntervalSince(appleEpoch) * 1_000_000_000)
    sqlite3_bind_int64(statement, 1, sinceNanos)

    var messages: [Message] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        let nanos = sqlite3_column_int64(statement, 1)
        messages.append(Message(
            id: columnText(statement, 0) ?? UUID().uuidString,
            at: appleEpoch.addingTimeInterval(Double(nanos) / 1_000_000_000),
            fromMe: sqlite3_column_int(statement, 2) == 1,
            sender: sqlite3_column_int(statement, 2) == 1 ? nil : columnText(statement, 6),
            chat: columnText(statement, 7),
            chatName: columnText(statement, 8).flatMap { $0.isEmpty ? nil : $0 },
            text: columnText(statement, 3).flatMap { $0.isEmpty ? nil : $0 }
                ?? columnBlob(statement, 4).flatMap(decodeAttributedBody),
            hasAttachments: sqlite3_column_int(statement, 5) == 1
        ))
    }
    return messages
}

func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    sqlite3_column_text(statement, index).map { String(cString: $0) }
}

func columnBlob(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
    guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
}

// Newer macOS versions often leave `text` empty and store the message as an archived
// NSAttributedString ("typedstream") in `attributedBody`. NSUnarchiver is deprecated,
// but it is the only system API that reads the typedstream format.
func decodeAttributedBody(_ data: Data) -> String? {
    if let unarchiver = NSUnarchiver(forReadingWith: data),
       let decoded = unarchiver.decodeObject() as? NSAttributedString {
        return decoded.string
    }
    return nil
}

// MARK: - Writing the snapshot

func write(_ snapshot: Snapshot, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(snapshot)

    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

    // Atomic write, owner-only: these are your private messages.
    let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(getpid()).tmp")
    FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600])
    _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
}

// MARK: - Main

let options = Options.parse(CommandLine.arguments)
let now = Date()
let since = now.addingTimeInterval(-options.hours * 3600)

let snapshot: Snapshot
var exitCode: Int32 = 0
do {
    let messages = try readMessages(since: since)
    snapshot = Snapshot(status: "ok", detail: nil, generatedAt: now, since: since,
                        hours: options.hours, messageCount: messages.count, messages: messages)
} catch let error as ExportError {
    snapshot = Snapshot(status: error.code, detail: error.detail, generatedAt: now, since: since,
                        hours: options.hours, messageCount: 0, messages: [])
    exitCode = 2
} catch {
    snapshot = Snapshot(status: "unexpected_error", detail: "\(error)", generatedAt: now, since: since,
                        hours: options.hours, messageCount: 0, messages: [])
    exitCode = 1
}

do {
    try write(snapshot, to: options.output)
    FileHandle.standardError.write(
        "messages-digest: \(snapshot.status), \(snapshot.messageCount) messages -> \(options.output.path)\n"
            .data(using: .utf8)!)
} catch {
    FileHandle.standardError.write(
        "messages-digest: could not write \(options.output.path): \(error)\n".data(using: .utf8)!)
    exitCode = 1
}
exit(exitCode)
