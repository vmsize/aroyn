# Using Aroyn

Open [aroyn.xyz](https://aroyn.xyz/) without signing in. Its dashboard preview is illustrative. Choose **Open dashboard → Sign in with Discord** to access your account; private runtime data requires your own authorization.

## Hub 4.3.96

The public manifest was independently checked as selecting **4.3.96** on 2026-10-12. The regular launch command is:

```luau
loadstring(game:HttpGet("https://aroyn.xyz/scripts/loader.luau"))()
```

This executes downloaded Luau in a compatible Greedy Growers environment. Read the source; the website does not run scripts in your browser. The owner tested the exact immutable 4.3.96 file on Windows/Potassium and Android/Delta. See [release identity and limitations](client-release.md) and [compatibility](compatibility.md).

The custom interface provides eight navigation pages. Seed buying, collection, compost, market and pet feeding start only when you intentionally enable their controls. Automation remains off during startup and preference/profile restoration.

## Connect the Dashboard

1. Sign in to the web Dashboard with Discord. Generate/view your dashboard key from the account/avatar UI when needed.
2. In Hub **4.3.96**, open **Settings → Dashboard and preferences**. Enter the key and choose **Link**. The credential is saved separately from preferences.
3. Use **Auto-connect Dashboard** to permit reconnection of a saved link on later launches. Optional connection failure does not prevent the local Hub from opening.
4. View **Dashboard → Runtime**; other sections show inventory, activity, statistics and supported fields when the running client supplies them.
5. **Disconnect** stops the current connection and reconnect intent. **Unlink** removes the saved link; do not confuse ordinary window teardown with explicit unlinking.

Older 4.3.95 puts the linking controls in **Session**. Existing published Hub docs may still describe that layout; use the version-specific instructions above for 4.3.96.

Treat the key as a password. Never expose it in screenshots, reports, issues or chat. If reconnect fails, check the saved link, Auto-connect setting and matching service configuration; do not share the key to diagnose it.

## Preferences, recovery and updates

Preferences use named profiles and AutoSave when local file capabilities are available. AutoSave can be disabled in Settings. A successful saved profile retains a previous recovery copy; **Restore previous saved profile** is an explicit action. Invalid/corrupt records are reported instead of trusted. Filesystem failures may leave session-only behavior; this is not a guarantee against every interrupted write.

Loading preferences does not enable automation. Keep recovery files when diagnosing a problem. Deliberate downgrade to 4.3.95 has different legacy restore behavior and can restore automation ON; close the active client and check toggles after downgrading.

Rerun the same normal loader to download the manifest-selected release. A manifest change does not replace an already running client. The loader checks size/HTML fallback, not the published SHA256 inside Roblox. See [release verification](release-verification.md).

## Account data

Avatar menu → **Account data** supports export and account deletion. Deletion requires a recent Discord sign-in and typing `DELETE`; it revokes Aroyn sessions/keys, not your Discord or Roblox accounts. Documented retention is 30 days for history and 7 days for snapshots without updates. See [scope and operational limits](account-data.md).

Aroyn is the renamed Veyra Hub; legacy technical names remain for compatibility. The static preview alone does not provide a working account/telemetry service. For your own setup, use [local development](setup.md). The [status page](https://aroyn.xyz/status/) checks HTTP availability rather than end-to-end account or gameplay behavior.
