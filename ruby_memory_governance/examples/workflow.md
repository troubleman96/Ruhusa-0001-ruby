# Example: human approval workflow

1. An AI agent proposes a high-impact memory.
2. Governance creates a pending approval request.
3. The memory is NOT yet visible in the memories table.
4. A human reviewer inspects the request.
5. The reviewer approves or rejects it.
6. If approved, the write occurs inside a transaction.
7. The audit log records the reviewer and decision.

This separation is the core human-in-the-loop safety pattern.
