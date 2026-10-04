require "json"
require "log"
require "file_utils"

module Positron::Plugins
  # SQLite / local database plugin — embedded SQLite over direct FFI
  # bindings to libsqlite3 (no external shard), following the project's
  # zero-dependency adapter style.
  #
  # Exposes to the frontend:
  #   - sqlite.query(sql, params?)  → { columns: [...], rows: [[...]...] }
  #   - sqlite.exec(sql, params?)   → { rows_affected, last_insert_id }
  #   - sqlite.close()
  #
  # Parameters are positional JSON values (String | Int | Float | null |
  # bool) bound by index. The database defaults to
  # `<app data dir>/<app_id>.db`; open is implicit on first use.
  class Sqlite < Positron::Plugin
    SQLITE_OK             =   0
    SQLITE_ROW            = 100
    SQLITE_DONE           = 101
    SQLITE_OPEN_READWRITE = 0x2
    SQLITE_OPEN_CREATE    = 0x4

    SQLITE_INTEGER = 1
    SQLITE_FLOAT   = 2
    SQLITE_TEXT    = 3
    SQLITE_NULL    = 5

    @db : Void*?

    def initialize(@app_id : String = "positron", @path : String? = nil)
    end

    def name : String
      "sqlite"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, Positron::CommandManifest)
      {
        "sqlite.query" => Positron::CommandManifest.new(
          name: "sqlite.query",
          args: [
            Positron::ArgumentManifest.new(name: "sql", type: "String"),
            Positron::ArgumentManifest.new(name: "params", type: "Array"),
          ],
          returns: "Object",
        ),
        "sqlite.exec" => Positron::CommandManifest.new(
          name: "sqlite.exec",
          args: [
            Positron::ArgumentManifest.new(name: "sql", type: "String"),
            Positron::ArgumentManifest.new(name: "params", type: "Array"),
          ],
          returns: "Object",
        ),
        "sqlite.close" => Positron::CommandManifest.new(name: "sqlite.close"),
      }
    end

    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      registry.register("sqlite.query") do |request|
        sql = str(request.args, "sql")
        params = request.args["params"]?.try(&.as_a?) || [] of JSON::Any

        columns, rows = query(sql, params)
        Positron::CommandResult.new(
          success: true,
          data: JSON.parse({columns: columns, rows: rows}.to_json)
        )
      end

      registry.register("sqlite.exec") do |request|
        sql = str(request.args, "sql")
        params = request.args["params"]?.try(&.as_a?) || [] of JSON::Any

        info = exec(sql, params)
        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(info.to_json)
        )
      end

      registry.register("sqlite.close") do |_request|
        close
        Positron::CommandResult.new(success: true, data: JSON.parse("{}"))
      end
    end

    # --- Database handling ---

    private def database : Void*
      @db ||= begin
        path = @path || default_db_path
        FileUtils.mkdir_p(File.dirname(path))
        db = Pointer(Void).null
        rc = LibSQLite3.sqlite3_open_v2(path, pointerof(db),
          SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        check(rc, db)
        db
      end
    end

    def close : Nil
      if db = @db
        LibSQLite3.sqlite3_close_v2(db)
        @db = nil
      end
    end

    def query(sql : String, params : Array(JSON::Any)) : {Array(String), Array(Array(JSON::Any))}
      stmt = Pointer(Void).null
      begin
        stmt = prepare(sql, params)
        columns = (0...LibSQLite3.sqlite3_column_count(stmt)).map do |i|
          String.new(LibSQLite3.sqlite3_column_name(stmt, i))
        end

        rows = [] of Array(JSON::Any)
        loop do
          rc = LibSQLite3.sqlite3_step(stmt)
          break if rc == SQLITE_DONE
          raise error_message if rc != SQLITE_ROW

          row = columns.each_index.map do |i|
            column_value(stmt, i)
          end.to_a
          rows << row
        end

        {columns, rows}
      ensure
        LibSQLite3.sqlite3_finalize(stmt) unless stmt.null?
      end
    end

    def exec(sql : String, params : Array(JSON::Any)) : NamedTuple(rows_affected: Int64, last_insert_id: Int64)
      stmt = prepare(sql, params)
      rc = LibSQLite3.sqlite3_step(stmt)
      raise error_message unless rc == SQLITE_DONE || rc == SQLITE_ROW
      LibSQLite3.sqlite3_finalize(stmt)

      db = database
      {
        rows_affected:  LibSQLite3.sqlite3_changes64(db),
        last_insert_id: LibSQLite3.sqlite3_last_insert_rowid(db),
      }
    end

    private def prepare(sql : String, params : Array(JSON::Any)) : Void*
      stmt = Pointer(Void).null
      rc = LibSQLite3.sqlite3_prepare_v2(database, sql, -1, pointerof(stmt), nil)
      raise error_message unless rc == SQLITE_OK

      params.each_with_index do |value, index|
        bind_param(stmt, index + 1, value)
      end
      stmt
    end

    private def bind_param(stmt : Void*, index : Int32, value : JSON::Any) : Nil
      rc = case value.raw
           when Nil     then LibSQLite3.sqlite3_bind_null(stmt, index)
           when Bool    then LibSQLite3.sqlite3_bind_int(stmt, index, value.as_bool ? 1 : 0)
           when Int64   then LibSQLite3.sqlite3_bind_int64(stmt, index, value.as_i64)
           when Float64 then LibSQLite3.sqlite3_bind_double(stmt, index, value.as_f)
           when String  then LibSQLite3.sqlite3_bind_text(stmt, index, value.as_s, -1, -1)
           else
             LibSQLite3.sqlite3_bind_text(stmt, index, value.to_json, -1, -1)
           end
      raise error_message unless rc == SQLITE_OK
    end

    private def column_value(stmt : Void*, index : Int32) : JSON::Any
      case LibSQLite3.sqlite3_column_type(stmt, index)
      when SQLITE_INTEGER
        JSON::Any.new(LibSQLite3.sqlite3_column_int64(stmt, index))
      when SQLITE_FLOAT
        JSON::Any.new(LibSQLite3.sqlite3_column_double(stmt, index))
      when SQLITE_NULL
        JSON.parse("null")
      else # TEXT and BLOB are returned as text
        text = LibSQLite3.sqlite3_column_text(stmt, index)
        JSON::Any.new(text.null? ? "" : String.new(text))
      end
    end

    private def default_db_path : String
      base = ENV["XDG_DATA_HOME"]? || File.join(ENV["HOME"]? || "/", ".local", "share")
      File.join(base, @app_id, "app.db")
    end

    private def check(rc : Int32, db : Void*) : Nil
      raise error_message(db) unless rc == SQLITE_OK
    end

    private def error_message(db : Pointer(Void)? = nil) : String
      handle = db || @db
      return "unknown sqlite error" unless handle
      String.new(LibSQLite3.sqlite3_errmsg(handle))
    end

    private def str(args : JSON::Any, key : String) : String
      args[key]?.try(&.as_s?) || ""
    end

    @[Link("sqlite3")]
    lib LibSQLite3
      fun sqlite3_open_v2(filename : LibC::Char*, db : Void**, flags : Int32, vfs : LibC::Char*) : Int32
      fun sqlite3_close_v2(db : Void*) : Int32
      fun sqlite3_prepare_v2(db : Void*, sql : LibC::Char*, byte_count : Int32, stmt : Void**, tail : LibC::Char**) : Int32
      fun sqlite3_step(stmt : Void*) : Int32
      fun sqlite3_finalize(stmt : Void*) : Int32
      fun sqlite3_column_count(stmt : Void*) : Int32
      fun sqlite3_column_name(stmt : Void*, index : Int32) : LibC::Char*
      fun sqlite3_column_type(stmt : Void*, index : Int32) : Int32
      fun sqlite3_column_int64(stmt : Void*, index : Int32) : Int64
      fun sqlite3_column_double(stmt : Void*, index : Int32) : Float64
      fun sqlite3_column_text(stmt : Void*, index : Int32) : LibC::Char*
      fun sqlite3_bind_null(stmt : Void*, index : Int32) : Int32
      fun sqlite3_bind_int(stmt : Void*, index : Int32, value : Int64) : Int32
      fun sqlite3_bind_int64(stmt : Void*, index : Int32, value : Int64) : Int32
      fun sqlite3_bind_double(stmt : Void*, index : Int32, value : Float64) : Int32
      fun sqlite3_bind_text(stmt : Void*, index : Int32, value : LibC::Char*, byte_count : Int32, destructor : Int64) : Int32
      fun sqlite3_changes64(db : Void*) : Int64
      fun sqlite3_last_insert_rowid(db : Void*) : Int64
      fun sqlite3_errmsg(db : Void*) : LibC::Char*
    end
  end
end
