# Third-party components

The homepage uses the independently written `aroyn-field.js` ASCII background under the project's MIT license. It uses native WebGL2/Canvas2D and locally available system fonts. It does not fetch React, vgpu or other renderer packages.

The previous React Bits ShapeWaves adaptation, mount, stylesheet and fallback are preserved in a private archive outside this source package. They are neither imported by the homepage nor included in this candidate. No redistribution rights for that previous component are claimed.

The homepage's dashboard screenshot is a local example using only illustrative account names and metrics. It does not represent a live user session or measured adoption.

## Supplied Roblox client assets

The readable Luau release carries the logo and navigation image strip embedded in the owner-supplied original client. The logo is covered by BRAND_ASSETS.md, separately from MIT code. The navigation strip was retained from the supplied client; no separately sourced icon-library files or external renderer were added. Its original upstream provenance was not independently established. Roblox platform assets referenced by asset ID are served by Roblox and are not redistributed as local image files.

## Development dependencies

The synthetic harness uses Miniflare, esbuild, ws and LinkeDOM as npm development dependencies; their upstream licenses remain applicable. They are not bundled into the browser site or Luau client. The exact graph is recorded in package-lock.json.

LinkeDOM 0.18.12 (Andrea Giammarchi / WebReflection) is used only for parsed-DOM component tests under its ISC license. Focus events are explicitly modeled in the harness; these checks do not certify browser tab order or screen-reader behavior. Dependency sources are fetched by npm, and are excluded from the website and source ZIP.
