-- Empty gate preserves old behavior until an operator activates a real ledger.
CREATE TABLE IF NOT EXISTS deletion_ledger_gate (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  ledger_id TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS account_deletion_receipts (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  ledger_id TEXT NOT NULL
);
-- Old in-flight code cannot remove the profile AND its pending job without
-- first having a receipt written by the new, ledger-aware finalizer.
CREATE TRIGGER IF NOT EXISTS guard_account_deletion_ledger
BEFORE DELETE ON users
WHEN EXISTS (SELECT 1 FROM deletion_ledger_gate WHERE singleton = 1)
 AND NOT EXISTS (
   SELECT 1 FROM account_deletion_receipts r JOIN deletion_ledger_gate g
     ON r.ledger_id = g.ledger_id
   WHERE r.user_id = OLD.id AND g.singleton = 1
 )
BEGIN
  SELECT RAISE(ABORT, 'Deletion ledger receipt required');
END;
