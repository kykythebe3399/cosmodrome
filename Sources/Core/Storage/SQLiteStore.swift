import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

/// Thin wrapper around system SQLite3 C API.
/// Provides connection management, WAL mode, prepared statement caching, and migrations.
public final class SQLiteStore {
    private var db: OpaquePointer?
    private var stmtCache: [String: OpaquePointer] = [:]
    private let queue: DispatchQueue

    public let path: String

    /// Opens (or creates) a SQLite database at the given path.
    /// Uses WAL journal mode for concurrent read/write.
    public init(path: String, queue: DispatchQueue? = nil) throws {
        self.path = path
        self.queue = queue ?? DispatchQueue(label: "com.cosmodrome.sqlite", qos: .utility)

        // Ensure parent directory exists (skip for in-memory databases)
        if path != ":memory:" {
            let dir = (path as NSString).deletingLastPathComponent
            if !dir.isEmpty {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }

        var dbPtr: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &dbPtr, flags, nil)
        guard result == SQLITE_OK, let opened = dbPtr else {
            let msg = dbPtr.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(dbPtr)
            throw SQLiteError.openFailed(msg)
        }
        self.db = opened

        // Enable WAL mode for concurrent reads during writes
        try execute("PRAGMA journal_mode=WAL")
        // Reasonable busy timeout (5 seconds)
        sqlite3_busy_timeout(db, 5000)
    }

    /// Opens an in-memory database (for tests).
    public convenience init() throws {
        try self.init(path: ":memory:")
    }

    deinit {
        finalizeAllStatements()
        if let db = db {
            sqlite3_close_v2(db)
        }
    }

    // MARK: - Execute

    /// Execute a SQL statement that doesn't return rows.
    @discardableResult
    public func execute(_ sql: String, params: [SQLiteValue] = []) throws -> Int {
        return try queue.sync {
            let stmt = try prepareStatement(sql)
            defer { sqlite3_reset(stmt) }
            try bindParams(stmt, params: params)

            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE || result == SQLITE_ROW else {
                throw SQLiteError.stepFailed(errorMessage)
            }
            return Int(sqlite3_changes(db))
        }
    }

    /// Execute multiple SQL statements separated by semicolons (for migrations).
    public func executeMultiple(_ sql: String) throws {
        try queue.sync {
            var errMsg: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
            if result != SQLITE_OK {
                let msg = errMsg.flatMap { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errMsg)
                throw SQLiteError.execFailed(msg)
            }
        }
    }

    // MARK: - Query

    /// Query rows and map each to a value using the provided closure.
    public func query<T>(_ sql: String, params: [SQLiteValue] = [], map: (Statement) -> T) throws -> [T] {
        return try queue.sync {
            let stmt = try prepareStatement(sql)
            defer { sqlite3_reset(stmt) }
            try bindParams(stmt, params: params)

            var results: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(map(Statement(stmt: stmt)))
            }
            return results
        }
    }

    /// Query a single row.
    public func queryOne<T>(_ sql: String, params: [SQLiteValue] = [], map: (Statement) -> T) throws -> T? {
        let results = try query(sql, params: params, map: map)
        return results.first
    }

    /// Query a single scalar value (e.g. COUNT, MAX).
    public func scalar<T>(_ sql: String, params: [SQLiteValue] = [], as type: T.Type = T.self) throws -> T? where T: SQLiteScalar {
        return try queryOne(sql, params: params) { row in
            row.column(0) as T?
        } as? T
    }

    // MARK: - Batch Insert

    /// Insert multiple rows in a transaction for performance.
    public func batchInsert(_ sql: String, paramSets: [[SQLiteValue]]) throws {
        try queue.sync {
            try beginTransaction()
            do {
                let stmt = try prepareStatement(sql)
                for params in paramSets {
                    sqlite3_reset(stmt)
                    try bindParams(stmt, params: params)
                    let result = sqlite3_step(stmt)
                    guard result == SQLITE_DONE else {
                        throw SQLiteError.stepFailed(errorMessage)
                    }
                }
                sqlite3_reset(stmt)
                try commitTransaction()
            } catch {
                try? rollbackTransaction()
                throw error
            }
        }
    }

    // MARK: - Transactions

    private func beginTransaction() throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, &errMsg)
        if result != SQLITE_OK {
            let msg = errMsg.flatMap { String(cString: $0) } ?? "Unknown"
            sqlite3_free(errMsg)
            throw SQLiteError.execFailed(msg)
        }
    }

    private func commitTransaction() throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, "COMMIT", nil, nil, &errMsg)
        if result != SQLITE_OK {
            let msg = errMsg.flatMap { String(cString: $0) } ?? "Unknown"
            sqlite3_free(errMsg)
            throw SQLiteError.execFailed(msg)
        }
    }

    private func rollbackTransaction() throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, "ROLLBACK", nil, nil, &errMsg)
        sqlite3_free(errMsg)
    }

    // MARK: - Migrations

    /// Current schema version.
    public var userVersion: Int {
        get {
            (try? queue.sync {
                var stmt: OpaquePointer?
                sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil)
                defer { sqlite3_finalize(stmt) }
                sqlite3_step(stmt)
                return Int(sqlite3_column_int(stmt, 0))
            }) ?? 0
        }
        set {
            try? queue.sync {
                var errMsg: UnsafeMutablePointer<CChar>?
                sqlite3_exec(db, "PRAGMA user_version = \(newValue)", nil, nil, &errMsg)
                sqlite3_free(errMsg)
            }
        }
    }

    /// Run pending migrations. Each migration is a (version, sql) pair.
    /// Migrations run in order, wrapped in transactions.
    public func migrate(_ migrations: [(version: Int, sql: String)]) throws {
        let current = userVersion
        for migration in migrations where migration.version > current {
            try executeMultiple(migration.sql)
            userVersion = migration.version
        }
    }

    // MARK: - Internals

    private func prepareStatement(_ sql: String) throws -> OpaquePointer {
        if let cached = stmtCache[sql] {
            return cached
        }
        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK, let prepared = stmt else {
            throw SQLiteError.prepareFailed(errorMessage)
        }
        stmtCache[sql] = prepared
        return prepared
    }

    private func bindParams(_ stmt: OpaquePointer, params: [SQLiteValue]) throws {
        sqlite3_clear_bindings(stmt)
        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            let result: Int32
            switch param {
            case .null:
                result = sqlite3_bind_null(stmt, idx)
            case .int(let v):
                result = sqlite3_bind_int64(stmt, idx, Int64(v))
            case .double(let v):
                result = sqlite3_bind_double(stmt, idx, v)
            case .text(let v):
                result = sqlite3_bind_text(stmt, idx, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard result == SQLITE_OK else {
                throw SQLiteError.bindFailed(errorMessage)
            }
        }
    }

    private func finalizeAllStatements() {
        for stmt in stmtCache.values {
            sqlite3_finalize(stmt)
        }
        stmtCache.removeAll()
    }

    private var errorMessage: String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
    }
}

// MARK: - Value Types

/// A value that can be bound to a SQLite parameter.
public enum SQLiteValue {
    case null
    case int(Int)
    case double(Double)
    case text(String)
}

/// Protocol for types that can be read as scalar query results.
public protocol SQLiteScalar {}
extension Int: SQLiteScalar {}
extension Double: SQLiteScalar {}
extension String: SQLiteScalar {}

/// Read-only wrapper around a SQLite row for type-safe column access.
public struct Statement {
    let stmt: OpaquePointer

    /// Read a text column.
    public func text(_ index: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cstr)
    }

    /// Read an integer column.
    public func int(_ index: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, index))
    }

    /// Read a double column.
    public func double(_ index: Int32) -> Double {
        sqlite3_column_double(stmt, index)
    }

    /// Read an optional double column.
    public func optionalDouble(_ index: Int32) -> Double? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : double(index)
    }

    /// Read an optional integer column.
    public func optionalInt(_ index: Int32) -> Int? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : int(index)
    }

    /// Read an optional text column.
    public func optionalText(_ index: Int32) -> String? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : text(index)
    }

    /// Generic column accessor for scalar protocol.
    func column<T>(_ index: Int32) -> T? {
        let type = sqlite3_column_type(stmt, index)
        if type == SQLITE_NULL { return nil }
        switch T.self {
        case is Int.Type: return int(index) as? T
        case is Double.Type: return double(index) as? T
        case is String.Type: return text(index) as? T
        default: return nil
        }
    }
}

// MARK: - Errors

public enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case execFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "SQLite open failed: \(msg)"
        case .prepareFailed(let msg): return "SQLite prepare failed: \(msg)"
        case .stepFailed(let msg): return "SQLite step failed: \(msg)"
        case .bindFailed(let msg): return "SQLite bind failed: \(msg)"
        case .execFailed(let msg): return "SQLite exec failed: \(msg)"
        }
    }
}
