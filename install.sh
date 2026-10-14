#!/bin/sh
# Installs the fonts FontPicker is curated for, then fontpicker itself.
#
#   ./install.sh                     whatever is missing on this Mac
#   ./install.sh --list              show what is and isn't installed; change nothing
#   ./install.sh --fonts "fira, monaspace" --no-app
#
# Fonts macOS already has, from anywhere, are left alone. --help lists the options.
set -eu

# Where a built fontpicker comes from when it can't be built on this Mac.
REPO=${FONTPICKER_REPO:-ryankschultze/ghostty-fontpicker}
RELEASE_URL=${FONTPICKER_RELEASE_URL:-https://github.com/$REPO/releases/latest/download/fontpicker-macos.tar.gz}
# Pinned, because family and file names have changed between Nerd Fonts releases.
NERD_FONTS_URL=${NERD_FONTS_URL:-https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1}

# One download per line: name | size in MB | the families to take from it | URL.
# Without a URL the download is <name>.tar.xz from the Nerd Fonts release. The families
# are the ones in SeedCatalog.swift; a test keeps the two lists the same.
manifest() {
    cat <<'FONTS'
Monaspace|19|MonaspiceNe Nerd Font,MonaspiceAr Nerd Font,MonaspiceRn Nerd Font,MonaspiceXe Nerd Font,MonaspiceKr Nerd Font
FiraCode|3|FiraCode Nerd Font
IosevkaTerm|92|IosevkaTerm Nerd Font
IosevkaTermSlab|56|IosevkaTermSlab Nerd Font
ZedMono|49|ZedMono Nerd Font
VictorMono|4|VictorMono Nerd Font
CascadiaCode|4|CaskaydiaCove Nerd Font
GeistMono|5|GeistMono Nerd Font
IntelOneMono|3|IntoneMono Nerd Font
LigaSFMono|22|Liga SFMono Nerd Font|https://github.com/shaunsingh/SFMono-Nerd-Font-Ligaturized/archive/dc5a3e6fcc2e16ad476b7be3c3c17c2273b260ea.tar.gz
Recursive|4|RecMonoLinear Nerd Font,RecMonoCasual Nerd Font,RecMonoSmCasual Nerd Font,RecMonoDuotone Nerd Font
Monoid|2|Monoid Nerd Font
IBMPlexMono|3|BlexMono Nerd Font
SourceCodePro|3|SauceCodePro Nerd Font
CascadiaMono|4|CaskaydiaMono Nerd Font
GoogleSansCode|3|GoogleSansCode Nerd Font
SpaceMono|2|SpaceMono Nerd Font
Mononoki|2|Mononoki Nerd Font
iA-Writer|4|iMWritingMono Nerd Font
CodeNewRoman|5|CodeNewRoman Nerd Font
UbuntuSans|4|UbuntuSansMono Nerd Font
UbuntuMono|3|UbuntuMono Nerd Font
FiraMono|3|FiraMono Nerd Font
Overpass|5|OverpassM Nerd Font
RobotoMono|4|RobotoMono Nerd Font
DejaVuSansMono|3|DejaVuSansM Nerd Font
LiberationMono|5|LiterationMono Nerd Font
MPlus|23|M+1Code Nerd Font,M+CodeLat50 Nerd Font,M+CodeLat60 Nerd Font
Monofur|3|Monofur Nerd Font
DepartureMono|2|DepartureMono Nerd Font
Monocraft|32|Monocraft|https://github.com/IdreesInc/Monocraft/releases/download/v4.2.1/Monocraft-nerd-fonts-patched.ttc
Terminus|3|Terminess Nerd Font
ProFont|4|ProFont IIx Nerd Font,ProFontWindows Nerd Font
ProggyClean|2|ProggyClean Nerd Font,ProggyCleanSZ Nerd Font,ProggyClean CE Nerd Font
FONTS
}

usage() {
    cat <<'EOF'
Installs the fonts FontPicker is curated for, then fontpicker itself.

  ./install.sh [options]

  --list            show which fonts are installed and which aren't, then stop
  --fonts <names>   only these, e.g. --fonts "fira, monaspace, iosevka"
  --no-fonts        skip the fonts
  --no-app          skip fontpicker
  --force           download fonts again even if macOS already has them
  --font-dir <dir>  where fonts go (default ~/Library/Fonts/FontPicker)
  --prefix <dir>    fontpicker goes in <dir>/bin (default ~/.local)
  -y, --yes         don't ask before downloading
EOF
}

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
    printf 'install.sh: %s\n' "$*" >&2
    exit 1
}

# $HOME/x shown as ~/x.
short() {
    case $1 in
        "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
        *) printf '%s' "$1" ;;
    esac
}

# plural 1 family families -> "1 family"; plural 3 family families -> "3 families".
plural() {
    if [ "$1" = 1 ]; then printf '1 %s' "$2"; else printf '%s %s' "$1" "$3"; fi
}

# "a,b,c" as one item per line.
items() { printf '%s\n' "$1" | tr ',' '\n'; }

# Every font family macOS has registered, one per line, into $tmp/families. AppKit is
# asked through osascript, which every Mac has, so nothing needs building first.
list_families() {
    osascript -l JavaScript -e 'ObjC.import("AppKit"); ObjC.deepUnwrap($.NSFontManager.sharedFontManager.availableFontFamilies).join("\n")' \
        > "$tmp/families" 2>/dev/null || : > "$tmp/families"
}

has_family() { grep -Fxq -- "$1" "$tmp/families"; }

# Whether a manifest row is one --fonts asked for: any term found in its name or families.
selected() {
    [ "$want_fonts" = all ] || printf '%s %s\n' "$1" "$2" | tr '[:upper:]' '[:lower:]' | grep -Fqf "$tmp/terms"
}

# Writes the selected rows to $tmp/rows as: name|MB|URL|families to install|families present.
survey() {
    manifest | while IFS='|' read -r name mb families url; do
        selected "$name" "$families" || continue
        missing=$(items "$families" | while IFS= read -r family; do
            if [ "$force" = 1 ] || ! has_family "$family"; then printf '%s,' "$family"; fi
        done)
        present=$(items "$families" | while IFS= read -r family; do
            if [ "$force" = 0 ] && has_family "$family"; then printf '%s,' "$family"; fi
        done)
        printf '%s|%s|%s|%s|%s\n' "$name" "$mb" "${url:-$NERD_FONTS_URL/$name.tar.xz}" "${missing%,}" "${present%,}"
    done > "$tmp/rows"
}

# $1 = all, or missing for only the rows with something to download.
print_rows() {
    while IFS='|' read -r name mb url missing present; do
        if [ -z "$missing" ]; then
            if [ "$1" = all ]; then
                printf '    %-16s %3s MB  installed  %s\n' "$name" "$mb" "$(printf '%s' "$present" | sed 's/,/, /g')"
            fi
        elif [ -z "$present" ]; then
            printf '    %-16s %3s MB  missing    %s\n' "$name" "$mb" "$(printf '%s' "$missing" | sed 's/,/, /g')"
        else
            printf '    %-16s %3s MB  partly     missing %s\n' "$name" "$mb" "$(printf '%s' "$missing" | sed 's/,/, /g')"
        fi
    done < "$tmp/rows"
}

confirm() {
    [ "$assume_yes" = 0 ] || return 0
    printf '%s [Y/n] ' "$1"
    if [ -t 0 ]; then
        read -r reply || reply=
    elif [ -t 1 ] && [ -r /dev/tty ]; then
        read -r reply < /dev/tty || reply= # piped in from curl: stdin is the script
    else
        say "yes (not a terminal)"
        return 0
    fi
    case $reply in [nN]*) return 1 ;; esac
}

# Takes the wanted families' files out of an archive. Nerd Fonts name a family's files
# after it with the spaces removed: "FiraCode Nerd Font" is FiraCodeNerdFont-*.ttf. Going
# by that also leaves behind the Mono and Propo variants, which the picker doesn't list.
unpack() {
    archive=$1 families=$2
    rm -rf "$tmp/unpacked"
    mkdir "$tmp/unpacked"
    set --
    while IFS= read -r family; do
        set -- "$@" "*$(printf '%s' "$family" | tr -d ' ')-*"
    done <<EOF
$(items "$families")
EOF
    tar -xf "$archive" -C "$tmp/unpacked" "$@" 2> /dev/null || true
    [ -n "$(find "$tmp/unpacked" -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' \) | head -n 1)" ] || return 1
    find "$tmp/unpacked" -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' \) -exec mv -f {} "$font_dir/" \;
}

install_fonts() {
    mkdir -p "$font_dir" "$tmp/dl"
    progress=-sS
    if [ -t 2 ]; then progress=--progress-bar; fi
    count=$(awk -F'|' '$4 != ""' "$tmp/rows" | wc -l | tr -d ' ')
    n=0 failed=0
    while IFS='|' read -r name mb url missing present <&3; do
        [ -n "$missing" ] || continue
        n=$((n + 1))
        say "  [$n/$count] $name"
        file=$tmp/dl/${url##*/}
        if ! curl -fL --retry 3 "$progress" -o "$file" "$url"; then
            warn "couldn't download $url"
            failed=1
            continue
        fi
        case $file in
            *.ttf | *.otf | *.ttc) mv -f "$file" "$font_dir/" ;;
            *)
                if ! unpack "$file" "$missing"; then
                    warn "found no font files for $name in $url"
                    failed=1
                fi
                ;;
        esac
        rm -f "$file"
    done 3< "$tmp/rows"
}

# The families that were to be installed and that macOS still doesn't list. It notices new
# files in a Fonts folder by itself, usually within a second or two.
still_missing() {
    wanted=$(awk -F'|' '$4 != "" { print $4 }' "$tmp/rows" | tr ',' '\n')
    tries=0
    while :; do
        list_families
        absent=$(printf '%s\n' "$wanted" | while IFS= read -r family; do
            has_family "$family" || printf '%s, ' "$family"
        done)
        tries=$((tries + 1))
        if [ -z "$absent" ] || [ "$tries" -ge 15 ]; then break; fi
        sleep 1
    done
    printf '%s' "${absent%, }"
}

fonts() {
    say "Fonts"
    list_families
    [ -s "$tmp/families" ] || warn "couldn't ask macOS which fonts it has; treating them all as missing"
    survey
    [ -s "$tmp/rows" ] || die "no font matches '$want_fonts'; --list shows the names"

    set -- $(awk -F'|' '{ m += split($4, a, ","); p += split($5, b, ","); if ($4 != "") { n++; mb += $2 } }
        END { print m + 0, p + 0, n + 0, mb + 0 }' "$tmp/rows")
    missing_count=$1 present_count=$2 downloads=$3 megabytes=$4

    if [ "$list_only" = 1 ]; then
        print_rows all
        say "  $(plural $((missing_count + present_count)) family families): $present_count installed, $missing_count missing"
        return 0
    fi
    if [ "$missing_count" = 0 ]; then
        say "  Nothing to do: $(plural "$present_count" family families) already installed."
        return 0
    fi
    say "  $(plural $((missing_count + present_count)) family families): $present_count already installed, $missing_count to install"
    print_rows missing
    say "  $(plural "$downloads" download downloads), about $megabytes MB, into $(short "$font_dir")"
    if ! confirm "  Download and install them?"; then
        say "  Skipped."
        return 0
    fi

    install_fonts
    absent=$(still_missing)
    if [ "$failed" = 0 ] && [ -z "$absent" ]; then
        say "  Installed $(plural "$missing_count" family families)."
    else
        problems=1
        [ -z "$absent" ] || warn "macOS doesn't list these: $absent"
        say "  Not everything was installed. Running this again retries what's missing."
    fi
}

# The folder this script is in, when that is a checkout of the repo. Empty when the script
# was piped in from curl.
checkout() {
    case $0 in
        */install.sh | install.sh)
            dir=$(cd "$(dirname "$0")" && pwd)
            if [ -f "$dir/Package.swift" ] && [ -d "$dir/Sources/fontpicker" ]; then printf '%s' "$dir"; fi
            ;;
    esac
}

# /usr/bin/swift exists on every Mac, but without developer tools it only opens the
# "install the command line developer tools" dialog. xcode-select says which it is.
has_swift() { xcode-select -p > /dev/null 2>&1 && xcrun -f swift > /dev/null 2>&1; }

app() {
    say "fontpicker"
    if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]; then
        problems=1
        warn "fontpicker needs macOS 14 or later; this is $(sw_vers -productVersion). Not installed."
        return 0
    fi

    built=
    repo_dir=$(checkout)
    if [ -n "$repo_dir" ] && has_swift; then
        say "  Building from $(short "$repo_dir")"
        if (cd "$repo_dir" && swift build -c release) > "$tmp/build.log" 2>&1; then
            built=$(cd "$repo_dir" && swift build -c release --show-bin-path)/fontpicker
        else
            tail -n 20 "$tmp/build.log" >&2
            warn "the build failed; falling back to the released binary"
        fi
    fi
    if [ -z "$built" ]; then
        say "  Downloading the released binary"
        curl -fsSL --retry 3 -o "$tmp/fontpicker.tar.gz" "$RELEASE_URL" ||
            die "couldn't download $RELEASE_URL. To build it instead: xcode-select --install, clone the repo, run ./install.sh there"
        tar -xzf "$tmp/fontpicker.tar.gz" -C "$tmp" fontpicker
        built=$tmp/fontpicker
    fi

    mkdir -p "$prefix/bin"
    install -m 755 "$built" "$prefix/bin/fontpicker"
    say "  Installed $(short "$prefix/bin/fontpicker") ($("$prefix/bin/fontpicker" version))"
    case ":$PATH:" in
        *":$prefix/bin:"*) ;;
        *)
            say "  $(short "$prefix/bin") isn't on your PATH. To add it:"
            say "    echo 'export PATH=\"$prefix/bin:\$PATH\"' >> ~/.zprofile && exec zsh -l"
            ;;
    esac
    installed_app=1
}

has_ghostty() {
    [ -d /Applications/Ghostty.app ] || [ -d "$HOME/Applications/Ghostty.app" ] || command -v ghostty > /dev/null 2>&1 ||
        [ -n "$(mdfind 'kMDItemCFBundleIdentifier == "com.mitchellh.ghostty"' 2> /dev/null | head -n 1)" ]
}

# Everything runs from here, so a download cut short can't run half of the script.
main() {
    prefix=$HOME/.local
    font_dir=$HOME/Library/Fonts/FontPicker
    want_fonts=all do_app=1 list_only=0 force=0 assume_yes=0 problems=0 installed_app=0

    while [ $# -gt 0 ]; do
        case $1 in
            --list) list_only=1 ;;
            --fonts) [ $# -ge 2 ] || die "--fonts needs a list of names"; want_fonts=$2; shift ;;
            --fonts=*) want_fonts=${1#*=} ;;
            --no-fonts) want_fonts= ;;
            --no-app) do_app=0 ;;
            --force) force=1 ;;
            --font-dir) [ $# -ge 2 ] || die "--font-dir needs a folder"; font_dir=$2; shift ;;
            --font-dir=*) font_dir=${1#*=} ;;
            --prefix) [ $# -ge 2 ] || die "--prefix needs a folder"; prefix=$2; shift ;;
            --prefix=*) prefix=${1#*=} ;;
            -y | --yes) assume_yes=1 ;;
            -h | --help) usage; exit 0 ;;
            *) die "unknown option '$1'; --help lists them" ;;
        esac
        shift
    done

    [ "$(uname -s)" = Darwin ] || die "this installs Mac fonts and a Mac app; it only runs on macOS"
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/fontpicker-install.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    trap 'exit 130' INT TERM

    has_ghostty || warn "Ghostty isn't installed (https://ghostty.org/download). Carrying on; the picker needs it only to apply a font."

    if [ -n "$want_fonts" ]; then
        if [ "$want_fonts" != all ]; then
            items "$want_fonts" | tr '[:upper:]' '[:lower:]' | sed 's/^ *//; s/ *$//' | grep -v '^$' > "$tmp/terms" ||
                die "--fonts needs at least one name"
        fi
        fonts
    fi
    if [ "$do_app" = 1 ] && [ "$list_only" = 0 ]; then app; fi

    if [ "$installed_app" = 1 ]; then say "Run 'fontpicker' to open the picker."; fi
    exit "$problems"
}

main "$@"
