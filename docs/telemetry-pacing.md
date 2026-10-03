# Full inventory telemetry pacing — 4.3.86

The owner observed stale telemetry on the published 4.3.85 client. In the actual
executor, six snapshot fragments of approximately 38 KB produced repeated abrupt
socket disconnects and no relay acknowledgments. A controlled trial showed that
single messages with up to 40 KB of padding received acknowledgments. Sending the
same full snapshot fragments with 150 ms yields between parts received fresh
acknowledgments without reconnecting during the trial. This establishes a
delivery problem with the synchronous burst on the observed connection; it does
not establish a universal executor frame-size limit.

4.3.86 yields between parts, checks client generation and socket identity before
each send, and ignores messages from obsolete sockets. Large transfers adjust
the subsequent delay to stay within a 96-frame/minute cadence (headroom below
the relay's 120-message/minute limit). Small snapshots retain the normal 5-second
delay. JSON-fragment limits, complete inventory contents, stable loader, server
code, HTTP persistence and presence intervals are unchanged.

Focused checks exercise the actual Luau sender with an executor queue requiring
yield, cancellation during a yield, socket replacement, and the worst-case
16-part cadence. Native local relay also passed a full synchronous burst; this
separately confirms that the relay supports the existing fragment envelopes.
Local and hosted tests alone are insufficient to prove real executor delivery.

Real-game validation and deployment evidence are recorded separately. Testing
uses the existing verification mode with farming disabled and configuration
writes suppressed. No mouse, keyboard or window control is required. Restricted
registration remains in effect; public-scale capacity is not claimed.
