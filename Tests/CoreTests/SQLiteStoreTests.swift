import XCTest
@testable import Core

final class SQLiteStoreTests: XCTestCase {

    func testOpenInMemory() throws {
        let store = try SQLiteStore()
        XCTAssertEqual(store.path, ":memory:")
    }

    func testCreateTableAndInsert() throws {
        let store = try SQLiteStore()
        try store.executeMultiple("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
        try store.execute("INSERT INTO test (name) VALUES (?)", params: [.text("hello")])

        let count: Int? = try store.scalar("SELECT COUNT(*) FROM test")
        XCTAssertEqual(count, 1)
    }

    func testQueryRows() throws {
        let store = try SQLiteStore()
        try store.executeMultiple("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT, value REAL)")
        try store.execute("INSERT INTO test (name, value) VALUES (?, ?)", params: [.text("a"), .double(1.5)])
        try store.execute("INSERT INTO test (name, value) VALUES (?, ?)", params: [.text("b"), .double(2.5)])

        let rows = try store.query("SELECT name, value FROM test ORDER BY name") { row in
            (name: row.text(0) ?? "", value: row.double(1))
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].name, "a")
        XCTAssertEqual(rows[0].value, 1.5)
        XCTAssertEqual(rows[1].name, "b")
    }

    func testQueryOne() throws {
        let store = try SQLiteStore()
        try store.executeMultiple("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
        try store.execute("INSERT INTO test (name) VALUES (?)", params: [.text("only")])

        let result = try store.queryOne("SELECT name FROM test") { row in
            row.text(0)
        }
        XCTAssertEqual(result, "only")
    }

    func testQueryOneEmpty() throws {
        let store = try SQLiteStore()
        try store.executeMultiple("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")

        let result = try store.queryOne("SELECT name FROM test") { row in
            row.text(0)
        } as String??
        XCTAssertNil(result)
    }

    func testBatchInsert() throws {
        let store = try SQLiteStore()
        try store.executeMultiple("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")

        let params: [[SQLiteValue]] = (0..<50).map { [.text("item_\($0)")] }
        try store.batchInsert("INSERT INTO test (name) VALUES (?)", paramSets: params)

        let count: Int? = try store.scalar("SELECT COUNT(*) FROM test")
        XCTAssertEqual(count, 50)
    }

    func testNullBinding() throws {
        let store = try SQLiteStore()
        try store.executeMultiple("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT, value REAL)")
        try store.execute("INSERT INTO test (name, value) VALUES (?, ?)", params: [.null, .double(1.0)])

        let row = try store.queryOne("SELECT name, value FROM test") { row in
            (name: row.optionalText(0), value: row.double(1))
        }
        XCTAssertNil(row?.name)
        XCTAssertEqual(row?.value, 1.0)
    }

    func testMigrations() throws {
        let store = try SQLiteStore()
        XCTAssertEqual(store.userVersion, 0)

        try store.migrate([
            (version: 1, sql: "CREATE TABLE v1 (id INTEGER PRIMARY KEY)"),
            (version: 2, sql: "CREATE TABLE v2 (id INTEGER PRIMARY KEY)"),
        ])
        XCTAssertEqual(store.userVersion, 2)

        // Running again should be a no-op
        try store.migrate([
            (version: 1, sql: "CREATE TABLE v1_again (id INTEGER PRIMARY KEY)"),
            (version: 2, sql: "CREATE TABLE v2_again (id INTEGER PRIMARY KEY)"),
        ])
        XCTAssertEqual(store.userVersion, 2)
    }

    func testMigrationsSkipAlreadyApplied() throws {
        let store = try SQLiteStore()
        try store.migrate([
            (version: 1, sql: "CREATE TABLE first (id INTEGER PRIMARY KEY)"),
        ])
        XCTAssertEqual(store.userVersion, 1)

        // Only version 2 should run
        try store.migrate([
            (version: 1, sql: "THIS WOULD FAIL IF RUN"),
            (version: 2, sql: "CREATE TABLE second (id INTEGER PRIMARY KEY)"),
        ])
        XCTAssertEqual(store.userVersion, 2)
    }

    func testExecuteReturnsChangedRows() throws {
        let store = try SQLiteStore()
        try store.executeMultiple("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
        try store.execute("INSERT INTO test (name) VALUES (?)", params: [.text("a")])
        try store.execute("INSERT INTO test (name) VALUES (?)", params: [.text("b")])

        let changed = try store.execute("DELETE FROM test WHERE name = ?", params: [.text("a")])
        XCTAssertEqual(changed, 1)
    }

    func testWALMode() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let dbPath = tmpDir.appendingPathComponent("test_wal_\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let store = try SQLiteStore(path: dbPath)
        let mode = try store.queryOne("PRAGMA journal_mode") { $0.text(0) ?? "" }
        XCTAssertEqual(mode, "wal")
        _ = store // keep alive
    }

    func testOptionalColumnAccessors() throws {
        let store = try SQLiteStore()
        try store.executeMultiple("CREATE TABLE test (id INTEGER PRIMARY KEY, val_int INTEGER, val_double REAL, val_text TEXT)")
        try store.execute("INSERT INTO test (val_int, val_double, val_text) VALUES (?, ?, ?)", params: [.null, .null, .null])

        let row = try store.queryOne("SELECT val_int, val_double, val_text FROM test") { row in
            (optInt: row.optionalInt(0), optDouble: row.optionalDouble(1), optText: row.optionalText(2))
        }
        XCTAssertNil(row?.optInt)
        XCTAssertNil(row?.optDouble)
        XCTAssertNil(row?.optText)
    }
}
