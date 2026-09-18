# Asset provenance

This record covers the redistributable dashboard and fixture artwork in this
repository. The governing rule is conservative: if the exact source or rights
for an asset cannot be proven, the asset is not redistributed.

## Disposition of unresolved assets

The former files under `dashboard/icons/` were byte-identical to the supplied
template icon files: the `outline`, `bold`, and `twotone` variants had no
license, README, copyright, or attribution record. Exact rights to redistribute
those loose files were not proven, so none of those source files is retained in
the dashboard.

The stock Flutter template launcher artwork in both checked-in fixture apps
was also removed. It had no local provenance record and is not needed by the
conformance behavior.

## Dashboard icon assets

The 22 files in `dashboard/icons/` are now pinned snapshots of the Lucide icon
set. Existing filenames and references are intentionally retained for path
compatibility; only the SVG contents changed. Each file remains a 24 x 24 SVG
and uses `#171717`, which keeps the prior external-`<img>` rendering color.
The dashboard markup already marks these images as decorative with empty `alt`
text and `aria-hidden="true"`; no accessibility-bearing markup was changed.

### Library, version, and source

- Library: Lucide.
- Version: `1.27.0`, release tag `1.27.0`.
- Immutable commit: `4aec3f892fd6c23063bc2fead83c899b5d412b1c`.
- Project: <https://github.com/lucide-icons/lucide>
- Release evidence: <https://github.com/lucide-icons/lucide/releases/tag/1.27.0>
- License evidence: <https://github.com/lucide-icons/lucide/blob/4aec3f892fd6c23063bc2fead83c899b5d412b1c/LICENSE>
- No runtime package dependency was added; these are vendored SVG snapshots.

The source mapping is:

| Shipped file | Lucide source | Preserved dashboard meaning |
| --- | --- | --- |
| `activity_outline.svg` | `activity.svg` | Deployment/activity |
| `arrow_down_outline.svg` | `chevron-down.svg` | Select/menu disclosure |
| `arrow_right_outline_2.svg` | `arrow-right.svg` | Submit CTA direction |
| `box_outline.svg` | `package.svg` | Artifacts/package |
| `category_2_outline.svg` | `layout-grid.svg` | Applications/category |
| `clipboard_text_outline.svg` | `clipboard-list.svg` | Patches and audit |
| `close_circle_outline.svg` | `circle-x.svg` | Dismiss/close |
| `document_text_outline.svg` | `file-text.svg` | Releases/document |
| `global_outline.svg` | `globe.svg` | Environments/global scope |
| `home_outline.svg` | `house.svg` | Overview/home |
| `logout_bold.svg` | `log-out.svg` | Sign out |
| `logout_outline.svg` | `log-out.svg` | Sign out |
| `menu_outline_2.svg` | `menu.svg` | Mobile navigation menu |
| `message_text_outline.svg` | `message-square-text.svg` | Messages/help |
| `moon_outline.svg` | `moon.svg` | Dark theme |
| `profile_outline.svg` | `user-round.svg` | Account/profile |
| `profile_twotone.svg` | `user-round.svg` | Account/profile |
| `refresh_outline.svg` | `refresh-cw.svg` | Refresh/reload |
| `search_normal_outline.svg` | `search.svg` | Search |
| `setting_outline.svg` | `settings.svg` | Settings |
| `shield_security_outline.svg` | `shield-check.svg` | Security |
| `sun_outline.svg` | `sun.svg` | Light theme |

Every source is available at the immutable commit using the corresponding
path, for example:

<https://raw.githubusercontent.com/lucide-icons/lucide/4aec3f892fd6c23063bc2fead83c899b5d412b1c/icons/activity.svg>

Replace `activity.svg` with the source name in the table for the other files.

### License and redistribution requirements

Lucide's pinned license is ISC. The Lucide license also identifies its
Feather-derived icons as MIT-licensed. The local set includes the following
Feather-derived source names: `arrow-right`, `chevron-down`, `log-out`,
`moon`, and `search`; the `circle-x` source uses the listed `circle` and `x`
primitives. The notices below are kept with this provenance record alongside
the vendored files.

```text
ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

For the Feather-derived portions:

```text
The MIT License (MIT)

Copyright (c) 2013-present Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The SVGs are modified only to retain the dashboard's `#171717` external-image
color and to add a source pointer comment. Those changes are permitted by the
licenses above and do not add new third-party material.

## Project-owned Hyfens assets

The following assets are original Hyfens material or deterministic local
fixtures. They do not depend on stock images, app screenshots, third-party
logos, or copied branding.

| Asset scope | Provenance and requirements |
| --- | --- |
| `dashboard/brand-mark.svg` | Project-owned Hyfens artwork, Copyright © Auvana Ventures Private Limited. Its geometry matches the mark described in the maintainer-provided Hyfens brand-guidelines HTML and source Affinity document, which are design references and are not redistributed here. The approved colors used here are Hyfens Orange `#FD5510` and Void Black `#0C0C0C`. This record does not grant trademark permission; follow `TRADEMARKS.md`. |
| `fixtures/flutter_conformance_app/assets/images/waypoint/hero-coast.svg` | Original local vector illustration; the file contains its own title/description for “A quiet coastal route.” |
| `fixtures/flutter_conformance_app/assets/images/waypoint/jaipur.svg` | Original local vector illustration; the file contains its own title/description for “Jaipur morning.” |
| `fixtures/flutter_conformance_app/assets/images/waypoint/kyoto.svg` | Original local vector illustration; the file contains its own title/description for “Kyoto evening.” |
| `fixtures/flutter_conformance_app/assets/images/waypoint/lisbon.svg` | Original local vector illustration; the file contains its own title/description for “Lisbon hillside.” |
| `fixtures/flutter_conformance_app/assets/images/waypoint/reykjavik.svg` | Original local vector illustration; the file contains its own title/description for “Reykjavik winter light.” |
| `fixtures/flutter_conformance_app/assets/video/waypoint-route-preview.mp4` | Silent, deterministic abstract route animation generated locally with FFmpeg `color` and `drawbox` filters. The exact command is recorded in `fixtures/flutter_conformance_app/assets/ATTRIBUTIONS.md`; no remote footage is used. |
| `fixtures/flutter_conformance_app/assets/data/*.json` | Hand-authored deterministic local mock payloads. They contain no credentials or remote media URLs. |

The five SVG scenes and the video are used by the Waypoint fixture through the
asset paths in `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_asset_paths.dart`
and the local JSON payloads. Their semantics and dimensions were not changed.

## Fixture app launcher artwork

Both checked-in Flutter apps now use the same project-owned source:
`dashboard/brand-mark.svg`.

- `fixtures/flutter_conformance_app/android/app/src/main/res/mipmap-*/ic_launcher.png`
- `fixtures/flutter_conformance_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`
- `fixtures/flutter_toolchain_app/android/app/src/main/res/mipmap-*/ic_launcher.png`
- `fixtures/flutter_toolchain_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`

The former Flutter-template images were replaced with opaque RGB PNGs using the
Hyfens mark at 80% of the canvas and `#0C0C0C` padding/background. Every
declared Android and iOS pixel dimension and every `Contents.json` filename
mapping is unchanged. The rasterization uses macOS `sips` from the SVG source
at the target inner size, pads to the declared canvas, and uses FFmpeg's
`format=rgb24` output to remove alpha from the final platform icons. No
third-party artwork or icon library is present in these PNGs.

The brand mark is project-owned source material, not a Lucide or Flutter asset.
It remains subject to the draft trademark policy in `TRADEMARKS.md`; the
Apache-2.0 source license and trademark permissions are separate.

The iOS `LaunchImage` files remain the existing 1 x 1 transparent placeholders,
and the Android launch backgrounds remain framework-color-only resources. They
contain no third-party artwork and were not changed.

## Inter font

`fixtures/flutter_conformance_app/assets/fonts/InterVariable.ttf` is sourced
from the official Inter repository at immutable commit
`e3a3d4c57d5ecc01453a575621882a384c1995a3`:

<https://raw.githubusercontent.com/rsms/inter/e3a3d4c57d5ecc01453a575621882a384c1995a3/docs/font-files/InterVariable.ttf>

The accompanying `fixtures/flutter_conformance_app/assets/fonts/Inter-OFL.txt`
is the repository's license file at that commit. The font is licensed under
the SIL Open Font License 1.1 by The Inter Project Authors. The local license
copy and the download evidence are also recorded in
`fixtures/flutter_conformance_app/assets/ATTRIBUTIONS.md`.

## Scope note

Ignored directories such as `fixtures/.phase1c-*`,
`fixtures/.hyfens-physical-acceptance.*`, and generated `build/` output are
disposable local evidence/build artifacts, not release assets. They were not
modified as part of this closure.
