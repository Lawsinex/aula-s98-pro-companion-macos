# Design — Library Rail

The selected 4 October 2026 reference is the Library Rail concept with the project's own keycap icon replacing the invented A. This supersedes the previous Anodised visual specification.

## Layout

The full editor uses a 34-point native titlebar band, an 84-point icon destination rail, a 280-point Lighting library and the remaining width as the keyboard workspace. The five destinations remain Lighting, Clock, Presets, Apps and Settings. All twenty effects are accessible as named list rows; the selected row has a subtle warm fill and checkmark.

The workspace contains the device heading and preset menu, the existing photographic keyboard, one output-control rail, and an inline circular colour wheel with saved colours, hex input, colour brightness and a calibration entry. Status and Apply are adjacent to the colour workflow. At narrow widths controls stack and the workspace scrolls. The minimum editor size is 980 × 680; the default is 1320 × 940.

## Tokens

- Workspace black: #000000, required by the supplied hardware photograph.
- Native titlebar: #151515.
- Surface: #141414; control well: #1C1C1C.
- Quiet divider: #292929; input edge: #484848.
- Primary text: #F2F3F5; secondary: #A8A8A8.
- Accent: #FFC799; selected row: #302820.
- SF Pro system typography; SF Mono for hexadecimal values.
- Control radius 8 points; ordinary controls 32 points high.

Use spacing and typography before containers. No ambient coloured wash or film grain in application chrome. The keyboard, swatches and colour wheels own saturated colour. Increase Contrast promotes shared edges and separators.

## Assets and behaviour

Use the bundled AppIcon.icns (the project's own keycap mark; AULA's logo is not used, as the app is unofficial). Use the real photograph and offline WebGL preview already in the project. Use SF Symbols for interface icons. No synthetic keyboard art.

The menu panel shares these tokens, controls and state. Every existing hardware and persistence workflow remains functional. The inline colour editor previews without `SAVE`, commits after pointer release, and commits coalesced keyboard/accessibility edits after a short idle boundary. Temporary calibration probes are separate from queued saves. Calibration remains target-versus-observed display calibration; it never changes USB RGB bytes. Per-key painting is also available through a native key-picker popover and VoiceOver controls.

USB state is explicit. A disconnected fixture says Preview only and offers connection recovery. Applied means a completed, acknowledged lighting job. The fixture model is isolated from saved preferences and real HID.
