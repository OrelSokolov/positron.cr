{% if flag?(:unix) || flag?(:win32) %}
  # The SQLite plugin binds libsqlite3 directly; it is an opt-in require
  # (`require "positron/plugins/sqlite/plugin"`) so applications without
  # a local database do not link it. This spec runs where the C library is
  # available (Linux/macOS CI runners; Windows links the system
  # winsqlite3.dll shipped with Win10+).
  require "../src/positron"
  require "../src/positron/plugins/sqlite/plugin"
  require "spec"
  require "json"
  require "file_utils"

  describe Positron::Plugins::Sqlite do
    it "creates tables, inserts, and queries with bound parameters" do
      dir = File.join(Dir.tempdir, "positron-sqlite-spec-#{Random::Secure.hex(6)}")
      db_path = File.join(dir, "test.db")

      plugin = Positron::Plugins::Sqlite.new(app_id: "specapp", path: db_path)
      registry = Positron::CommandRegistry.new
      state = Positron::StateManager.new
      plugin.bind(registry, state)

      request = ->(name : String, args : String) do
        registry.dispatch(Positron::CommandRequest.new(
          id: "spec", name: name, args: JSON.parse(args)))
      end

      begin
        created = request.call("sqlite.exec", %({"sql":"CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT, done INTEGER)"}))
        created.success.should be_true

        inserted = request.call("sqlite.exec", %({"sql":"INSERT INTO notes (title, done) VALUES (?, ?)","params":["first note", 0]}))
        inserted.success.should be_true
        inserted.data["last_insert_id"].as_i.should eq(1)

        request.call("sqlite.exec", %({"sql":"INSERT INTO notes (title, done) VALUES (?, ?)","params":["second note", 1]}))

        result = request.call("sqlite.query", %({"sql":"SELECT id, title, done FROM notes WHERE done = ? ORDER BY id","params":[1]}))
        result.success.should be_true
        result.data["columns"].as_a.map(&.to_s).should eq(["id", "title", "done"])
        result.data["rows"].as_a.size.should eq(1)
        row = result.data["rows"].as_a.first
        row[0].as_i.should eq(2)
        row[1].as_s.should eq("second note")
        row[2].as_i.should eq(1)

        # NULL round-trip
        request.call("sqlite.exec", %({"sql":"INSERT INTO notes (title, done) VALUES (?, ?)","params":[null, 0]}))
        nulls = request.call("sqlite.query", %({"sql":"SELECT title FROM notes WHERE id = 3"}))
        nulls.data["rows"].as_a.first[0].to_json.should eq("null")

        closed = request.call("sqlite.close", %({}))
        closed.success.should be_true
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
{% else %}
  # Windows runners have no libsqlite3 in the default toolchain; skipped.
  describe "Positron::Plugins::Sqlite (skipped on this platform)" do
    it "is not built here" do
      true.should be_true
    end
  end
{% end %}
