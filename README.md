# CopyPal 📋

A quick-and-dirty clipboard history menu bar app for macOS. Keeps your last
10 copied text snippets one click away — a DIY take on CopyClip.

- Single-file Swift app, no Xcode project, no dependencies
- Menu bar dropdown with the last 10 text entries (press 1–9/0 to pick one)
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
plain-text entries, deduplicated, newest first. That's the whole trick —
see [`main.swift`](main.swift).
