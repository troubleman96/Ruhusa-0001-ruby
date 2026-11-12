require "fileutils"
require "time"

module RMG
  class Governance
    def initialize(store:, policy: Policy.new)
      @store = store
      @db = store.db
      @policy = policy
    end

    # AI or application code calls propose. It never writes directly.
    def propose_create(content:, type: "fact", importance: 5, tags: [], requested_by: "agent")
      raise ArgumentError, "content cannot be blank" if content.to_s.strip.empty?
      raise ArgumentError, "importance must be 1..10" unless (1..10).cover?(importance.to_i)

      decision = @policy.decision(action: "create", importance: importance)
      if decision == :deny
        return { status: "denied", reason: "Policy denied this operation" }
      end

      if decision == :allow
        id = create_memory(content, type, importance, tags)
        @store.audit(actor: requested_by, event: "memory.created.auto",
                     target_type: "memory", target_id: id,
                     details: "Automatically approved low-risk create")
        return { status: "approved_automatically", memory_id: id }
      end

      request_id = create_request(
        action: "create", memory_id: nil, content: content, type: type,
        importance: importance, tags: tags, reason: "Policy requires human review",
        requested_by: requested_by
      )
      { status: "pending_approval", request_id: request_id }
    end

    def propose_update(memory_id:, content:, requested_by: "agent")
      memory = @db.get_first_row("SELECT * FROM memories WHERE id = ?", memory_id)
      raise ArgumentError, "memory not found" unless memory
      raise ArgumentError, "content cannot be blank" if content.to_s.strip.empty?

      request_id = create_request(
        action: "update", memory_id: memory_id, content: content,
        type: memory["memory_type"], importance: memory["importance"],
        tags: memory["tags"].to_s.split(","), reason: "Memory updates require review",
        requested_by: requested_by
      )
      { status: "pending_approval", request_id: request_id }
    end

    def propose_delete(memory_id:, requested_by: "agent")
      memory = @db.get_first_row("SELECT * FROM memories WHERE id = ?", memory_id)
      raise ArgumentError, "memory not found" unless memory

      request_id = create_request(
        action: "delete", memory_id: memory_id, content: nil,
        type: nil, importance: nil, tags: [],
        reason: "Deletion requires review", requested_by: requested_by
      )
      { status: "pending_approval", request_id: request_id }
    end

    def pending
      @db.execute("SELECT * FROM approval_requests WHERE status='pending' ORDER BY created_at")
    end

    def approve(request_id:, reviewer:, note: "")
      raise ArgumentError, "reviewer is required" if reviewer.to_s.strip.empty?
      request = pending_request(request_id)
      raise ArgumentError, "request is not pending" unless request

      @db.transaction
      begin
        memory_id = execute_request(request)
        @db.execute(
          "UPDATE approval_requests SET status='approved', reviewed_by=?, review_note=?, reviewed_at=? WHERE id=? AND status='pending'",
          [reviewer, note, @store.now, request_id]
        )
        @store.audit(actor: reviewer, event: "approval.granted",
                     target_type: "approval_request", target_id: request_id,
                     details: "Approved #{request['action']} request; memory_id=#{memory_id}")
        @db.commit
        { status: "approved", memory_id: memory_id }
      rescue
        @db.rollback
        raise
      end
    end

    def reject(request_id:, reviewer:, note: "")
      raise ArgumentError, "reviewer is required" if reviewer.to_s.strip.empty?
      request = pending_request(request_id)
      raise ArgumentError, "request is not pending" unless request

      @db.execute(
        "UPDATE approval_requests SET status='rejected', reviewed_by=?, review_note=?, reviewed_at=? WHERE id=? AND status='pending'",
        [reviewer, note, @store.now, request_id]
      )
      @store.audit(actor: reviewer, event: "approval.rejected",
                   target_type: "approval_request", target_id: request_id,
                   details: "Rejected #{request['action']} request: #{note}")
      { status: "rejected" }
    end

    def memories
      @db.execute("SELECT * FROM memories ORDER BY id DESC")
    end

    def audit_log(limit: 50)
      @db.execute("SELECT * FROM audit_events ORDER BY id DESC LIMIT ?", limit.to_i)
    end

    private

    def create_memory(content, type, importance, tags)
      now = @store.now
      @db.execute(
        "INSERT INTO memories(content,memory_type,importance,tags,created_at,updated_at) VALUES(?,?,?,?,?,?)",
        [content, type, importance.to_i, Array(tags).join(","), now, now]
      )
      @db.last_insert_row_id
    end

    def create_request(action:, memory_id:, content:, type:, importance:, tags:, reason:, requested_by:)
      sql = <<~SQL
        INSERT INTO approval_requests
        (action,memory_id,proposed_content,proposed_type,proposed_importance,
         proposed_tags,reason,requested_by,created_at)
        VALUES(?,?,?,?,?,?,?,?,?)
      SQL
      params = [action, memory_id, content, type, importance, Array(tags).join(","),
                reason, requested_by, @store.now]
      @db.execute(sql, params)
      id = @db.last_insert_row_id
      @store.audit(actor: requested_by, event: "approval.requested",
                   target_type: "approval_request", target_id: id,
                   details: "Requested #{action}: #{reason}")
      id
    end

    def pending_request(id)
      @db.get_first_row("SELECT * FROM approval_requests WHERE id=? AND status='pending'", id.to_i)
    end

    def execute_request(request)
      case request["action"]
      when "create"
        create_memory(request["proposed_content"], request["proposed_type"],
                      request["proposed_importance"], request["proposed_tags"].to_s.split(","))
      when "update"
        @db.execute(
          "UPDATE memories SET content=?, updated_at=? WHERE id=?",
          [request["proposed_content"], @store.now, request["memory_id"]]
        )
        request["memory_id"]
      when "delete"
        @db.execute("DELETE FROM memories WHERE id=?", request["memory_id"])
        nil
      else
        raise "Unknown action in approval request"
      end
    end
  end
end
