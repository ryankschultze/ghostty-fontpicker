# FontPicker

Preview the fixed-width fonts installed on your Mac and apply one to
[Ghostty](https://ghostty.org), with its stylistic sets, ligatures, weight and italics,
without hand-editing the config.

It is a native version of a browser specimen page for Nerd Fonts: the same workbench, but
reading the fonts actually installed, and with an **Apply to Ghostty** button in place of
copy and paste.

## How it plugs into Ghostty

Ghostty has no plugin API, so this is a companion app that uses the hooks Ghostty does
have:

- **Config include.** Applying a font writes `fontpicker.ghostty` next to your Ghostty
  config and, the first time, adds one line to the end of your config:
  `config-file = ?fontpicker.ghostty`. The picker asks before adding it. Nothing else in
  your config is touched. Ghostty loads included files last, so the picker's font wins
  over one set earlier in your config.
- **Reload signal.** Ghostty 1.2 and later reload their config on `SIGUSR2`, and a reload
  rebuilds the font of every terminal that is already open. So applying a font changes
  your open terminals in place. Older versions are never signalled (the signal would
  terminate them); the picker tells you to press `cmd+shift+,` instead.

`fontpicker reset` removes the include and the line again.

## Install

On a Mac with Ghostty, macOS 14 or later:

```sh
curl -fsSL https://raw.githubusercontent.com/ryankschultze/ghostty-fontpicker/main/install.sh | sh
```

or, from a checkout, `./install.sh`. It does two things, in this order:

1. **Fonts.** It asks macOS which of the picker's 46 families it already has, however they
   got there, lists the rest and asks before downloading them into
   `~/Library/Fonts/FontPicker`. On a Mac with none of them that is 34 downloads, about
   385 MB, and 1.6 GB once unpacked. Most are from the
   [Nerd Fonts](https://www.nerdfonts.com) 3.5.1 release; Monocraft and Liga SFMono come
   from their own projects. Only the families the picker lists are taken from each
   download, without their `Mono` and `Propo` variants.
2. **fontpicker**, into `~/.local/bin`. In a checkout with a Swift toolchain it is built
   from source. Otherwise the binary from the latest release is downloaded; it runs on
   Apple silicon and Intel.

```sh
./install.sh --list                      # what is and isn't installed; changes nothing
./install.sh --fonts "fira, monaspace"   # only some of the fonts
./install.sh --no-fonts                  # only fontpicker
./install.sh --help
```

To remove it all: `fontpicker reset`, then delete `~/.local/bin/fontpicker` and
`~/Library/Fonts/FontPicker`.

## Build and run

Building needs a Swift toolchain. The Command Line Tools are enough; Xcode is not needed.

```sh
make build        # .build/release/fontpicker
make run          # build, then open the picker
make app          # build/FontPicker.app, for the Dock or Spotlight
make install      # copy to ~/.local/bin (PREFIX=/usr/local to change)
make test
make dist         # build/fontpicker-macos.tar.gz, the binary a release carries
```

To open it from inside Ghostty, add either of these to your Ghostty config once
`fontpicker` is on your `PATH`. Ghostty can't run a command from a keybind, so both type
the command into the focused terminal, which only helps at a shell prompt.

```
keybind = super+shift+k=text:fontpicker\n
command-palette-entry = title:"Font Picker",description:"Preview and choose a font",action:"text:fontpicker\n"
```

## Using the window

| | |
|---|---|
| `↑` `↓` (or `←` `→`, `j` `k`) | previous / next font |
| `⌘F` or `/` | filter the list |
| `space` | start or stop drift |
| `⌘↩` | apply to Ghostty |

- **Features** are the font's stylistic sets and character variants. Each chip shows the
  affected glyphs before and after; click to switch, and click again to step through a
  variant's alternates. Switches are remembered per font.
- **Live** applies every change as you make it, so your open terminals follow along while
  you browse. **Revert** puts the font back the way it was when the picker opened.
- **Drift** plays the features by itself: *Tour* one at a time, *LFO* on slow overlapping
  waves, *Random* a flip or two per beat. *Keep this* freezes what is on screen.
- **Shortlist** lines starred fonts up with the same three lines of text.
- **Fonts: Nerd / All** switches between Nerd Fonts and every fixed-width family
  installed. The `Mono` and `Propo` variants of a Nerd Font are hidden when the plain
  family is installed: Ghostty resizes Nerd Font icons by its own rules whichever font
  they come from, so the three look the same there.

## Command line

```sh
fontpicker list [--all] [--json]
fontpicker info "Fira Code" [--json]
fontpicker apply "Monaspice Neon" --features "ss01, ss02, cv01=2" --size 13
fontpicker apply "Fira Code" --italic-from "Victor Mono" --print   # show the lines, change nothing
fontpicker reset
fontpicker paths
```

Family names match the full name, the short name, or a unique part of either.

## How close is the preview?

The stage is drawn with Core Text, the font engine Ghostty uses on macOS, and laid out
by Ghostty's own rules (`CellMetrics.swift` follows `src/font/Metrics.zig` and
`src/font/face/coretext.zig` in Ghostty 1.3):

- the cell is the widest ASCII advance by the font's line height, rounded to whole device
  pixels;
- every glyph is placed in the cell of the character it came from, so ligatures are
  exactly as wide as what they replace;
- a missing bold is stroked and a missing italic is skewed 15°, as Ghostty does;
- Nerd Font icons are fitted into one cell, or two when a space follows.

It is still a preview. Ghostty rasterizes with its own renderer, and settings the picker
doesn't know about (`adjust-cell-height`, `font-thicken`, `window-colorspace`, your
theme's colours) change the result. Apply, or switch on Live, to see the real thing.

## Layout

```
Sources/FontPickerCore/   discovery, feature probing, cell metrics, Ghostty config. No UI.
Sources/fontpicker/       the SwiftUI window and the CLI
Tests/                    config text, config location, reload gating, metrics
install.sh                installs the fonts, then fontpicker
scripts/gen-seed.mjs      regenerates SeedCatalog.swift from the specimen page
scripts/bundle.sh         wraps the executable in FontPicker.app
```

What a feature does is found by shaping text with it off and on and comparing glyphs,
not by reading the font's substitution tables. Results are cached in
`~/Library/Caches/FontPicker`; the picker's own state lives in
`~/Library/Application Support/FontPicker`.

Display names, the grouping, the per-font notes, which italics are cursive and the
default feature presets can't be measured. They come from the specimen page through
`make seed`. Fonts it doesn't mention still appear, grouped by what was measured. The page
embeds the fonts it shows, so it isn't in this repo: `make seed` reads a copy named
`Nerd Font Specimens.html` in this folder, or pass a path to `scripts/gen-seed.mjs`.

### Notes for working on it

- `@State` is a macro in the macOS 27 SDK and its compiler plugin ships only with Xcode.
  Views use `@Local` (`Controls.swift`), a thin wrapper over the same storage, so
  `swift build` works with the Command Line Tools alone.
- `swift test` on its own fails to find the Swift Testing macros under the Command Line
  Tools; `make test` passes the plugin path.
- `fontpicker snapshot --out window.png [--font NAME] [--dark] [--drift tour]` renders the
  window to a PNG without showing it, for checking layout changes.
- `install.sh` has its own list of downloads, because it runs before anything is built. A
  test fails if that list and `SeedCatalog.swift` name different families. A new family
  needs both: its notes in the specimen page (`make seed`) and its download in `install.sh`.
- To release: bump `Version.swift`, `make dist`, then
  `gh release create v<version> build/fontpicker-macos.tar.gz`. `install.sh` always
  downloads from the latest release.
