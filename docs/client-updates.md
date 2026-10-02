# Stable launch command and restored GUI updates — 2026-10-02

The owner confirmed the 4.3.81 game checks worked. The direct versioned command was for candidate verification. The regular command remains:

```lua
loadstring(game:HttpGet("https://aroyn-staging.pages.dev/scripts/loader.luau"))()
```

The loader now reads the public static scripts/version.json and constructs a fixed-origin immutable release path from a validated version. Publishing a later asset and manifest together selects it without changing the saved loader command. Old release bytes remain unchanged. Manifest and loader responses use no-store; JSON retains its JSON Content-Type rather than inheriting text/plain.

The GUI update label and WebSocket notification code were present, but staging had an empty update URL and an early disabled return. Release 4.3.82 removes that override and restores the static manifest check. The existing header label appears for a newer release, and activity records that version once. A running client is not forcibly replaced; rerunning the same loader retrieves the current release. Checks run after startup and then every 30 minutes, using no account credentials or D1 writes.

Both immutable earlier clients 4.3.80/4.3.81 stay archived. Existing already-running 4.3.81 instances keep their disabled update-check code; restart once via the stable loader to receive 4.3.82. Its Auto Market logic is unchanged from the owner-tested 4.3.81.

The local gate passed 20 suites / 234 groups, including twelve loader/update/actual GUI-label groups and seventeen cancellation/compiler groups. Invalid paths, unsupported games, manifest/download/compile/startup failures, stale replies and one-time notice activity are covered. This is Luau with HTTP/game stubs, not a real Roblox render test. See [local evidence](local-client-updates-gate-2026-10-02.json).

Publication and hosted checks are pending at this capture. General registration remains restricted. Real menu/theme checks, ordinary daily cleanup, deferred full-day D1 and targeted independent review remain release gates.
