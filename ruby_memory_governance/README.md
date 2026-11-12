# Ruby Memory Governance Engine

A small Ruby + SQLite project demonstrating human-in-the-loop governance for AI memory operations.

## What it demonstrates

- An agent proposes memory operations instead of writing directly to storage.
- A policy decides whether an operation is automatically allowed or needs review.
- High-importance creates, updates, and deletes enter a human approval queue.
- A human reviewer approves or rejects pending requests.
- Approved actions execute in a database transaction.
- Audit events record who requested and reviewed an action.

## Requirements

- Ruby 3.1+
- Bundler
- SQLite

## Install

```bash
bundle install
```

## Try the workflow

A low-risk memory (importance 5) is automatically stored:

```bash
bundle exec ruby bin/memory-governance propose "I am learning Ruby" 5
```

A high-importance memory requires human approval:

```bash
bundle exec ruby bin/memory-governance propose "My long-term goal is to build AI agents" 10
```

The output gives a request ID. Inspect the approval queue:

```bash
bundle exec ruby bin/memory-governance pending
```

Approve it (replace 1 with the actual request ID):

```bash
bundle exec ruby bin/memory-governance approve 1 "human-reviewer" "This is an intentional learning goal"
```

Or reject it:

```bash
bundle exec ruby bin/memory-governance reject 1 "human-reviewer" "This should not be stored"
```

Updates and deletions always require review:

```bash
bundle exec ruby bin/memory-governance memories
bundle exec ruby bin/memory-governance update 1 "Updated memory text"
bundle exec ruby bin/memory-governance delete 1
bundle exec ruby bin/memory-governance pending
```

Review the audit trail:

```bash
bundle exec ruby bin/memory-governance audit
```

## Architecture

```text
Agent / CLI
    |
    v
Governance service
    |
    +--> Policy (allow / human / deny)
    |
    +--> Approval queue (pending / approved / rejected)
    |
    +--> Store (SQLite)
    |
    +--> Audit log
```

## Important design notes

This is a learning prototype, not a production security boundary. The CLI uses a reviewer name as a demonstration; a real application must authenticate reviewers and enforce authorization on the server. Add CSRF protection for browser approval screens, immutable/append-only audit storage, rate limits, policy versioning, and concurrency protection before production use.

The demo intentionally uses keyword-free memory storage: its focus is governance and approval workflow, not semantic retrieval or LLM integration.
