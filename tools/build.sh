#!/usr/bin/env bash
# Build Soms In Space as a Linux arm64 binary (embedded pck) for the
# phyBOARD LYRA AM62x. See BUILD.md for details.
set -euo pipefail

GODOT_SERIES="4.7"
TEMPLATE_VERSION="4.7.1.stable"
TEMPLATE_URL="https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz"
PRESET="Linux"
OUTPUT="build/Soms-In-Space.arm64"

GODOT=${GODOT:-godot}
INSTALL_TEMPLATES=${INSTALL_TEMPLATES:-0}
EXPORT_MODE="--export-release"
DO_IMPORT=1
KEEP_IMPORT_CHANGES=0

usage() {
	cat <<USAGE
Usage: tools/build.sh [options]

Exports the "$PRESET" preset to $OUTPUT (aarch64 ELF, pck embedded).

Options:
  --install-templates    Download and install the $TEMPLATE_VERSION export
                         templates if missing (~1.2 GB download).
                         Same as INSTALL_TEMPLATES=1.
  --debug                Export a debug build (--export-debug) instead of release.
  --no-import            Skip the separate 'godot --import' pass.
  --keep-import-changes  Do not revert *.import files that Godot rewrote.
  -h, --help             Show this help.

Environment:
  GODOT                  Godot $GODOT_SERIES.x editor binary (default: godot on PATH).
  INSTALL_TEMPLATES=1    Same as --install-templates.
USAGE
}

die() { echo "build.sh: error: $*" >&2; exit 1; }
TMP_DIR=""
IMPORT_REVERT_ARMED=0

# Godot rewrites tracked *.import files when it imports; put them back on the
# way out (success or failure) so the work tree stays clean.
revert_import_changes() {
	[[ "$IMPORT_REVERT_ARMED" == "1" && "$KEEP_IMPORT_CHANGES" == "0" ]] || return 0
	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
	local changed
	changed="$(git diff --name-only -- '*.import' | wc -l)"
	if [[ "$changed" -gt 0 ]]; then
		git checkout -- '*.import'
		log "Reverted $changed *.import file(s) rewritten by Godot (use --keep-import-changes to keep them)"
	else
		log "No *.import changes to revert"
	fi
}
cleanup() {
	revert_import_changes || true
	if [[ -n "$TMP_DIR" ]]; then rm -rf "$TMP_DIR"; fi
}
trap cleanup EXIT
log() { echo "==> $*"; }

while [[ $# -gt 0 ]]; do
	case "$1" in
		--install-templates) INSTALL_TEMPLATES=1 ;;
		--debug) EXPORT_MODE="--export-debug" ;;
		--no-import) DO_IMPORT=0 ;;
		--keep-import-changes) KEEP_IMPORT_CHANGES=1 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; die "unknown option: $1" ;;
	esac
	shift
done

# Run from the repo root regardless of the caller's cwd.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
[[ -f project.godot ]] || die "project.godot not found in $REPO_ROOT"

# --- Godot editor ----------------------------------------------------------
command -v "$GODOT" >/dev/null 2>&1 || die "Godot not found ('$GODOT').
Install the Godot $TEMPLATE_VERSION editor for Linux x86_64, put it on PATH as
'godot', or set GODOT=/path/to/Godot_v4.7.1-stable_linux.x86_64. See BUILD.md."
GODOT_VERSION="$("$GODOT" --version 2>/dev/null | tail -n 1 || true)"
[[ "$GODOT_VERSION" == "$GODOT_SERIES".* ]] || die "'$GODOT' reports version '${GODOT_VERSION:-<none>}';
this project needs a Godot $GODOT_SERIES.x editor (templates: $TEMPLATE_VERSION)."
log "Godot: $GODOT ($GODOT_VERSION)"
case "$GODOT_VERSION" in
	"$TEMPLATE_VERSION"*) ;;
	*) echo "warning: editor is $GODOT_VERSION but this script installs/checks $TEMPLATE_VERSION templates;" \
		"Godot will look for templates matching its own version." >&2 ;;
esac

# --- Export templates ------------------------------------------------------
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$TEMPLATE_VERSION"

templates_ok() {
	[[ -f "$TEMPLATE_DIR/linux_release.arm64" && -f "$TEMPLATE_DIR/linux_debug.arm64" \
		&& -f "$TEMPLATE_DIR/version.txt" ]] \
		&& [[ "$(tr -d '[:space:]' < "$TEMPLATE_DIR/version.txt")" == "$TEMPLATE_VERSION" ]]
}

install_templates() {
	command -v curl >/dev/null 2>&1 || die "curl is required to download templates"
	command -v unzip >/dev/null 2>&1 || die "unzip is required to extract templates"
	TMP_DIR="$(mktemp -d)"
	local tmp="$TMP_DIR"
	log "Downloading $TEMPLATE_URL (~1.2 GB)"
	curl -fL --retry 5 --retry-delay 5 --retry-connrefused -o "$tmp/templates.tpz" "$TEMPLATE_URL" \
		|| die "template download failed"
	mkdir -p "$TEMPLATE_DIR"
	log "Extracting arm64 templates to $TEMPLATE_DIR"
	unzip -j -o "$tmp/templates.tpz" 'templates/linux_release.arm64' \
		'templates/linux_debug.arm64' 'templates/version.txt' -d "$TEMPLATE_DIR" \
		|| die "extracting templates failed"
	rm -f "$tmp/templates.tpz"
	templates_ok || die "installed templates in $TEMPLATE_DIR are incomplete or not $TEMPLATE_VERSION"
	log "Templates installed"
}

if templates_ok; then
	log "Templates: $TEMPLATE_DIR"
elif [[ "$INSTALL_TEMPLATES" == "1" ]]; then
	install_templates
else
	cat >&2 <<MSG
build.sh: error: Godot $TEMPLATE_VERSION arm64 export templates not found in
  $TEMPLATE_DIR
(need linux_release.arm64, linux_debug.arm64 and version.txt containing $TEMPLATE_VERSION)

Re-run with --install-templates to download them automatically, or install manually:

  curl -fL --retry 5 -o /tmp/templates.tpz \\
    $TEMPLATE_URL
  mkdir -p "$TEMPLATE_DIR"
  unzip -j -o /tmp/templates.tpz 'templates/linux_release.arm64' \\
    'templates/linux_debug.arm64' 'templates/version.txt' \\
    -d "$TEMPLATE_DIR"
  rm /tmp/templates.tpz
MSG
	exit 1
fi

# --- Preset sanity ---------------------------------------------------------
# A non-empty custom_template path overrides the installed templates; an old
# commit pointed these at a developer's local engine build.
for kind in debug release; do
	path="$(sed -n "s/^custom_template\/$kind=\"\(.*\)\"$/\1/p" export_presets.cfg | head -n 1)"
	if [[ -n "$path" && ! -f "$path" ]]; then
		die "export_presets.cfg sets custom_template/$kind=\"$path\", which does not exist.
Set custom_template/debug and custom_template/release to \"\" so the installed
$TEMPLATE_VERSION templates are used (see BUILD.md, Troubleshooting)."
	fi
done
grep -q '^binary_format/architecture="arm64"' export_presets.cfg \
	|| die "export_presets.cfg: binary_format/architecture is not \"arm64\" (see BUILD.md)"

# --- Import + export -------------------------------------------------------
IMPORT_REVERT_ARMED=1
if [[ "$DO_IMPORT" == "1" ]]; then
	log "Importing assets (first run on a fresh clone takes a while)"
	start=$SECONDS
	"$GODOT" --headless --path . --import || die "asset import failed"
	log "Import done in $((SECONDS - start)) s"
fi

mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"
log "Exporting preset '$PRESET' ($EXPORT_MODE) to $OUTPUT"
start=$SECONDS
"$GODOT" --headless --path . "$EXPORT_MODE" "$PRESET" "$OUTPUT" || die "export failed"
log "Export done in $((SECONDS - start)) s"

# --- Verify the binary -----------------------------------------------------
[[ -s "$OUTPUT" ]] || die "export produced no file at $OUTPUT"
if command -v file >/dev/null 2>&1; then
	desc="$(file -b "$OUTPUT")"
	[[ "$desc" == ELF*aarch64* ]] || die "$OUTPUT is not an aarch64 ELF: $desc
Check binary_format/architecture=\"arm64\" in export_presets.cfg."
else
	# ELF magic (7f 45 4c 46) and e_machine (offset 18, little endian) == 0xb7 (EM_AARCH64).
	magic="$(od -An -tx1 -N4 "$OUTPUT" | tr -d ' \n')"
	machine="$(od -An -tu2 -j18 -N2 "$OUTPUT" | tr -d ' \n')"
	[[ "$magic" == "7f454c46" && "$machine" == "183" ]] || die "$OUTPUT is not an aarch64 ELF (magic=$magic e_machine=$machine)"
	desc="ELF, e_machine=183 (aarch64)"
fi
chmod +x "$OUTPUT"

size_bytes="$(wc -c < "$OUTPUT" | tr -d ' ')"
log "Built $REPO_ROOT/$OUTPUT"
echo "    $desc"
echo "    $size_bytes bytes ($(( (size_bytes + 500000) / 1000000 )) MB)"
