# FreeClean

A free, open replacement for CleanMyMac, available as a native SwiftUI app and a `freeclean` CLI.

**Safety:** everything goes to the **Trash**, so you can restore it. The one exception is the opt-in "Trash" category, which empties the Trash for good. FreeClean only touches your home folder and third-party apps in `/Applications`. It never needs sudo, and it refuses Apple apps and system paths.

## Features
| | App screen | CLI |
|---|---|---|
| Junk: user caches, logs, Xcode DerivedData/DeviceSupport/simulator caches, Homebrew/npm/pip/Yarn/Gradle/CocoaPods caches, Trash, old Downloads | Smart Scan | `freeclean scan`, `freeclean clean` |
| Large & old files in your home folder | Large & Old Files | `freeclean large` |
| App uninstaller + leftovers in `~/Library` | Uninstaller | `freeclean uninstall <App>` |
| Disk usage with drill-down | Disk Usage | `freeclean disk` |
| Memory pressure, top processes, launch agents | Memory & Startup | `freeclean memory`, `freeclean startup` |

## Build & install
Only Command Line Tools are needed, not Xcode.
```bash
scripts/bundle.sh --install
```
This puts the app in `~/Applications/FreeClean.app` and the CLI in `~/.local/bin/freeclean`. Without `--install`, the outputs stay in `build/`.

For full results (Trash, some app containers), grant **Full Disk Access** to FreeClean (and to your terminal for the CLI) in System Settings › Privacy & Security.

## CLI examples
```bash
freeclean scan -v                      # what can be cleaned
freeclean clean --dry-run              # preview default cleanup
freeclean clean -c xcode -c dev        # only Xcode + developer caches
freeclean large --min-size 1G --include-hidden
freeclean uninstall "Some App" --dry-run
freeclean startup --disable com.example.agent
```

## Tests
```bash
swift run freeclean-selftest
```
This is a plain executable rather than `swift test`, because XCTest and Swift Testing need full Xcode.
