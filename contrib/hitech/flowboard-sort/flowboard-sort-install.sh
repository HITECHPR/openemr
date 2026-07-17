#!/usr/bin/env bash
#
# flowboard-sort-install.sh
#
# Installs the Flow Board sortable-columns + default-sort patch into a normal
# (non-git) OpenEMR install using the GNU `patch` utility (-p1).
#
# Usage:
#   1. Copy this script AND flowboard-sort.tar.gz into the OpenEMR webroot
#      (the directory that contains interface/ and library/).
#   2. chmod +x flowboard-sort-install.sh
#   3. ./flowboard-sort-install.sh            # back up, dry-run, apply
#      ./flowboard-sort-install.sh --check    # dry-run only, change nothing
#      ./flowboard-sort-install.sh --rollback # restore the most recent backup
#
#   Optional: TARBALL=/path/to/flowboard-sort.tar.gz ./flowboard-sort-install.sh
#
# Non-destructive: it dry-runs first and aborts if the patch will not apply
# cleanly; if a hunk cannot match (a customized file) `patch` writes a *.rej and
# leaves the rest untouched. Timestamped backups are made before any change.

set -euo pipefail

# ---- config ---------------------------------------------------------------
TARBALL="${TARBALL:-./flowboard-sort.tar.gz}"
PATCH_REL="flowboard-sort/flowboard-sort.patch"
SUMS_REL="flowboard-sort/SHA256SUMS.txt"
TARGETS=(
    "interface/patient_tracker/patient_tracker.php"
    "library/globals.inc.php"
)
TS="$(date +%Y%m%d-%H%M%S)"

MODE="apply"
case "${1:-}" in
    --check|-n)   MODE="check" ;;
    --rollback)   MODE="rollback" ;;
    "")           MODE="apply" ;;
    *)            echo "Unknown option: $1"; echo "Use: --check | --rollback | (no arg to apply)"; exit 2 ;;
esac

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
grn()   { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()   { printf '\033[33m%s\033[0m\n' "$*"; }
die()   { red "ERROR: $*"; exit 1; }

# ---- rollback mode --------------------------------------------------------
if [ "$MODE" = "rollback" ]; then
    for f in "${TARGETS[@]}"; do
        last="$(ls -1t "${f}.flbsort.bak-"* 2>/dev/null | head -1 || true)"
        [ -n "$last" ] || die "No backup found for $f (looked for ${f}.flbsort.bak-*)"
        cp -p "$last" "$f"
        grn "restored $f  <-  $(basename "$last")"
    done
    grn "Rollback complete. Hard-refresh the browser."
    exit 0
fi

# ---- preconditions --------------------------------------------------------
echo "== Flow Board sort patch installer =="
echo "webroot: $(pwd)"

for f in "${TARGETS[@]}"; do
    [ -f "$f" ] || die "Not in the OpenEMR webroot? Missing: $f
Run this from the directory that contains interface/ and library/."
done
[ -f "$TARBALL" ] || die "Tarball not found: $TARBALL
Copy flowboard-sort.tar.gz next to this script, or set TARBALL=/path/to/it."
command -v patch >/dev/null 2>&1 || die "'patch' utility not found. Install it (e.g. apt-get install patch / yum install patch) or use the prebuilt/ drop-in method in APPLY.md."

# pick a PHP for the syntax check (prefer 8.2, which OpenEMR needs)
PHPBIN=""
for c in php8.2 php8.3 php; do
    if command -v "$c" >/dev/null 2>&1; then PHPBIN="$c"; break; fi
done

# ---- extract to a temp dir ------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tar -xzf "$TARBALL" -C "$WORK"
PATCH="$WORK/$PATCH_REL"
SUMS="$WORK/$SUMS_REL"
[ -f "$PATCH" ] || die "Patch not found inside tarball at $PATCH_REL"

# ---- report current state vs known checksums (informational) --------------
already_all=1
if [ -f "$SUMS" ] && command -v sha256sum >/dev/null 2>&1; then
    echo
    echo "-- checking current files against known checksums --"
    for f in "${TARGETS[@]}"; do
        cur="$(sha256sum "$f" | awk '{print $1}')"
        stock="$(grep "  $f\$" "$SUMS" | sed -n '1p' | awk '{print $1}')"
        new="$(grep "  $f\$" "$SUMS" | sed -n '2p' | awk '{print $1}')"
        if   [ "$cur" = "$stock" ]; then grn   "  $f: STOCK (clean apply expected)"; already_all=0
        elif [ "$cur" = "$new" ];   then ylw   "  $f: ALREADY PATCHED (matches target result)"
        else                             ylw   "  $f: locally modified — patch will try; a hunk may reject"; already_all=0
        fi
    done
else
    already_all=0
fi

# already fully patched -> nothing to do (clean exit, even on re-run)
if [ "$already_all" = 1 ]; then
    echo
    grn "Both files already match the patched result — nothing to do."
    exit 0
fi

# ---- dry-run gate ---------------------------------------------------------
echo
echo "-- dry-run (patch -p1 --dry-run) --"
if patch -t -p1 --dry-run < "$PATCH"; then
    grn "dry-run OK"
else
    echo
    die "Dry-run failed — nothing was changed.
If the files are already patched, you are done. Otherwise a file differs from
stock; apply by hand from the .rej, or send the production files to be re-based."
fi

if [ "$MODE" = "check" ]; then
    echo
    grn "--check only: no changes made."
    exit 0
fi

# ---- backup, then apply ---------------------------------------------------
echo
echo "-- backing up target files --"
declare -A OWN MODEB
for f in "${TARGETS[@]}"; do
    cp -p "$f" "${f}.flbsort.bak-${TS}"
    OWN["$f"]="$(stat -c '%U:%G' "$f")"
    MODEB["$f"]="$(stat -c '%a' "$f")"
    echo "  backed up $f -> ${f}.flbsort.bak-${TS}"
done

echo
echo "-- applying patch --"
patch -t -p1 < "$PATCH"

# ---- reject / ownership / lint checks -------------------------------------
rejs="$(find interface/patient_tracker library -name '*.rej' 2>/dev/null || true)"
if [ -n "$rejs" ]; then
    echo
    red "Some hunks were REJECTED (nothing lost — backups + .rej present):"
    echo "$rejs"
    red "Review the .rej files, or roll back with: $0 --rollback"
    exit 1
fi

# restore original owner/mode (patch preserves them in place, but be explicit)
for f in "${TARGETS[@]}"; do
    chown "${OWN[$f]}" "$f" 2>/dev/null || true
    chmod "${MODEB[$f]}" "$f" 2>/dev/null || true
done

if [ -n "$PHPBIN" ]; then
    echo
    echo "-- php -l ($PHPBIN) --"
    for f in "${TARGETS[@]}"; do "$PHPBIN" -l "$f"; done
else
    ylw "No php CLI found; skipped syntax check. Verify the two files load in the app."
fi

# ---- verify result checksums (informational) ------------------------------
if [ -f "$SUMS" ] && command -v sha256sum >/dev/null 2>&1; then
    echo
    echo "-- verifying patched result --"
    ok=1
    for f in "${TARGETS[@]}"; do
        cur="$(sha256sum "$f" | awk '{print $1}')"
        new="$(grep "  $f\$" "$SUMS" | sed -n '2p' | awk '{print $1}')"
        if [ "$cur" = "$new" ]; then grn "  $f: matches expected result"
        else ylw "  $f: differs from the reference build (expected if the file was locally customized)"; ok=0
        fi
    done
    [ "$ok" = 1 ] || true
fi

echo
grn "Done. Flow Board sort patch applied."
echo "Next:"
echo "  - Hard-refresh the browser once (inline JS/CSS changed)."
echo "  - Optional: Administration > Globals > Calendar to set the default sort;"
echo "    users can override under their own Settings > Calendar. No DB step needed."
echo "  - Rollback anytime: $0 --rollback"
