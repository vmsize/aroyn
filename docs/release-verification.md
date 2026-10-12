# Release verification boundaries

Use [product status](product-status.md) and the live public manifest to distinguish repository source, immutable hosted bytes and globally selected version.

## Verify a download locally

Example PowerShell, read-only network requests with files written locally:

```powershell
Invoke-RestMethod https://aroyn.xyz/scripts/version.json
Invoke-WebRequest https://aroyn.xyz/releases/4.3.96/greedy-growers.luau -OutFile ./AroynHub-4.3.96.luau
(Get-Item ./AroynHub-4.3.96.luau).Length
Get-FileHash ./AroynHub-4.3.96.luau -Algorithm SHA256
```

Expected size **836402**, SHA256 `f72f5bc0180c7fc9c7b92027f4a24a3adcbbc68713ae2fe44973b6974b1cf97e`. A successful HTTP status may still deliver an HTML fallback; check actual content, redirects, byte count and hash. The public loader validates version syntax, size and HTML fallback, but does not compute SHA256 inside Roblox.

For UI v0.1.0, download the [pinned code](https://lib.aroyn.xyz/stable/0.1.0/Aroyn.lua) and [manifest](https://lib.aroyn.xyz/stable/0.1.0/manifest.json); independently compare SHA256 and size. Current code: **232227 bytes**, SHA256 `afc4a8ff0f91e64ef4d99fc60e4a23b5c9e33e407051d40a37328c4c8c70689a`. Checksums from the same compromised host would not be independent authenticity evidence; signed attestations are not claimed here.

## Publication is a separate gate

Do not overwrite immutable releases. Source integration, reproducible build, notices, automated tests, exact native candidate approval, full frontend inventory, artifact publication, pointer activation and rollback authorization are separate responsibilities. GitHub documentation changes do not authorize any of them.

The completed 4.3.96 rollout published the immutable executable first, then changed only the global manifest's version/message after fresh verification. Historical instructions describing a combined upload remain historical. Future publication requires a current reviewed complete package and explicit authorization; never upload a sparse manifest-only directory over the whole site.

Record real evidence and preserve previous releases. Synthetic tests, compilation, browser checks and native platform observations must remain separately labeled. The read-only [Luau workflow](../.github/workflows/luau.yml) rebuilds both current artifacts and runs portable mocks from checked-in sources. The builders refuse a mismatched hash and never deploy, promote Latest or activate the public manifest. See [testing](testing.md) and each component README for local reproduction.
