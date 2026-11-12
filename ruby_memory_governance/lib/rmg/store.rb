require "fileutils"
require "time"

module RMG
  class Store
    attr_reader :db

    def initialize(path = "data/memory_governance.sqlite3")
      FileUtils.mkdir_p(File.dirname(path))
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = true
      schema!
    end

    def schema!
      db.execute_batch <<~SQL
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS memories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          content TEXT NOT NULL,
          memory_type TEXT NOT NULL DEFAULT 'fact',
          importance INTEGER NOT NULL DEFAULT 5,
          tags TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS approval_requests (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT NOT NULL,
          memory_id INTEGER,
          proposed_content TEXT,
          proposed_type TEXT,
          proposed_importance INTEGER,
          proposed_tags TEXT,
          reason TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          requested_by TEXT NOT NULL,
          reviewed_by TEXT,
          review_note TEXT,
          created_at TEXT NOT NULL,
          reviewed_at TEXT
        );

        CREATE TABLE IF NOT EXISTS audit_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          actor TEXT NOT NULL,
          event TEXT NOT NULL,
          target_type TEXT NOT NULL,
          target_id INTEGER,
          details TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
      SQL
    end

    def now
      Time.now.utc.iso8601
    end

    def audit(actor:, event:, target_type:, target_id:, details:)
      db.execute(
        "INSERT INTO audit_events(actor,event,target_type,target_id,details,created_at) VALUES(?,?,?,?,?,?)",
        [actor, event, target_type, target_id, details, now]
      )
    end

    def close
      db.close
    end
  end
end
