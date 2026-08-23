# CopyPal 📋

<img width="523" height="346" alt="Screenshot 2026-08-23 at 8 21 15 AM" src="https://github.com/user-attachments/assets/0768ba98-e203-49d3-b552-245cc66937c9" />

A quick-and-dirty clipboard history menu bar app for macOS. Keeps your last
10 copied text snippets one click away — a DIY take on CopyClip.

- Two small Swift files, no Xcode project, no dependencies
- Menu bar dropdown with the last 10 text entries (press 1–9/0 to pick one)
- **Semantic formatting**: each entry is detected and rendered accordingly —
  CSS colors (`#ff6600`, `rgb()`, `hsl()`) get a color swatch, emails an
  envelope, URLs a link icon, phone numbers a phone icon, file paths a
  folder, popular unix commands a terminal icon plus monospaced type, and
  "gibberish" gets tagged too — UUIDs a tag, hex hashes a number sign, and
  secret-looking jumbles (passwords, API keys, JWTs, base64) a key icon
- Skips password-manager copies (`org.nspasteboard.ConcealedType`)
- History persists across restarts (`~/Library/Application Support/CopyPal/history.json`)
- No Dock icon, no windows — just the menu bar

## Build & run

```sh
./build.sh
open CopyPal.app
```

Requires macOS 11+ and the Xcode command line tools (`xcode-select --install`).
The app is ad-hoc signed, so no Apple Developer account is needed for local use.

## Start at login

System Settings → General → Login Items → **+** → select `CopyPal.app`.

## How it works

macOS has no clipboard-change notification API, so CopyPal polls
`NSPasteboard.general.changeCount` a few times a second and records new
plain-text entries, deduplicated, newest first — see [`main.swift`](main.swift).

Classification ([`SemanticClassifier.swift`](SemanticClassifier.swift)) is
deliberately boring: regexes and small parsers for CSS colors, emails, and
URLs, `NSDataDetector` for phone numbers (whole-string matches only), a
does-it-exist check for file paths with spaces, and a command allowlist for
unix commands. UUIDs and hex hashes are exact format checks; secrets are
either a well-known token prefix (`ghp_`, `sk-`, `eyJ`…) or a
character-class-transition heuristic — random jumbles flip between upper,
lower, and digits almost every character, while camelCase identifiers and
product names don't, so `aB3xK9mQ2rTz` gets a key icon and
`iPhone15ProMax256GB` stays plain. Anything ambiguous stays plain — a
missing icon beats a wrong one.
