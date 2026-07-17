# Flow Board — Sortable Columns + Default-Sort Setting

Non-destructive change for a **normal (non-git) OpenEMR install**. Adds
per-column sorting to the Patient Flow Board plus a configurable default-sort
column/direction. Touches only two core files:

- `interface/patient_tracker/patient_tracker.php`  (clickable/sortable headers + JS sort)
- `library/globals.inc.php`  (two new user-specific globals)

No database migration. No module changes (doc-sign is unaffected — the row
`data-pid` / `data-apptstatus` attributes it relies on are preserved).

`git` is NOT required. The `patch` utility used below is the standalone GNU tool
(`/usr/bin/patch`); it works on plain files and needs no repository.

---

## Contents of this folder

- `flowboard-sort-install.sh` — automated installer (backup + dry-run + `patch -p1`
  + lint; also `--check` and `--rollback`). Easiest path — see below.
- `flowboard-sort.patch` — the unified diff (apply this with `patch`).
- `SHA256SUMS.txt` — checksums of the stock base files and of the patched result.
- `prebuilt/` — the two complete, already-patched files (drop-in alternative).
- `APPLY.md` — this file.

## Quick path — the installer script

From the OpenEMR webroot, with `flowboard-sort.tar.gz` and
`flowboard-sort-install.sh` copied in:

```bash
chmod +x flowboard-sort-install.sh
./flowboard-sort-install.sh --check   # dry-run only, changes nothing
./flowboard-sort-install.sh           # back up, apply, lint
./flowboard-sort-install.sh --rollback # undo (restores newest backup)
```

The manual steps below (Method A / Method B) remain available if you prefer to
apply by hand.

---

## Method A — apply the patch (preferred)

Run from the OpenEMR **webroot** (the directory that contains `interface/` and
`library/` — e.g. `/var/www/html/openemr`).

```bash
cd /var/www/html/openemr

# 1. Back up the two target files first
cp interface/patient_tracker/patient_tracker.php interface/patient_tracker/patient_tracker.php.bak
cp library/globals.inc.php library/globals.inc.php.bak

# 2. DRY-RUN first — this changes nothing, just reports whether it will apply:
patch -p1 --dry-run < /path/to/flowboard-sort.patch

# 3. If the dry-run says both files apply cleanly, apply for real:
patch -p1 < /path/to/flowboard-sort.patch

# 4. Syntax-check with the PHP that runs OpenEMR (>= 8.2):
php -l interface/patient_tracker/patient_tracker.php
php -l library/globals.inc.php
```

Preserve file ownership/permissions if you copied files in as root:
`chown` them back to the web user (e.g. `www-data` or `apache`) if needed.

### If a hunk is REJECTED
A rejection means the production copy of that file differs from stock (a
consultant edited it). `patch` writes a `*.rej` file next to the target and
leaves the rest applied — **nothing is destroyed**. Either merge the `.rej`
by hand, or restore from your `.bak` and send me that production file so I can
rebuild the patch against it exactly.

---

## Method B — drop-in the prebuilt files (only if Method A isn't usable)

Use this only if `patch` is unavailable AND you have confirmed the production
files are stock (unmodified). Verify with checksums first:

```bash
cd /var/www/html/openemr
sha256sum interface/patient_tracker/patient_tracker.php library/globals.inc.php
```

Compare against the **STOCK base** lines in `SHA256SUMS.txt`.

- **If they match** the stock-base checksums → the files are unmodified, so
  copying the prebuilt versions over them is equivalent to the patch and safe:
  ```bash
  cp interface/patient_tracker/patient_tracker.php interface/patient_tracker/patient_tracker.php.bak
  cp library/globals.inc.php library/globals.inc.php.bak
  cp /path/to/prebuilt/interface/patient_tracker/patient_tracker.php interface/patient_tracker/patient_tracker.php
  cp /path/to/prebuilt/library/globals.inc.php library/globals.inc.php
  # fix ownership if needed, then php -l both files
  ```
- **If they do NOT match** → the production files were customized. Do **not**
  drop-in (it would wipe those customizations). Use Method A, or send me the
  production copies and I'll rebuild the patch.

After copying, confirm each file now matches the **NEW patched result**
checksums in `SHA256SUMS.txt`.

---

## After applying (either method)

- **No DB step required.** The two new globals default correctly even before a
  row exists in the `globals` table (built-in fallback: column = Appt Time,
  direction = Ascending).
- To expose/persist them: **Administration → Globals → Calendar** now shows
  *Flow Board: Default Sort Column* and *…Default Sort Direction*. Each user may
  also override them under their own **Settings → Calendar**.
- Hard-refresh the browser once (inline JS/CSS changed).

## Rollback

```bash
cp interface/patient_tracker/patient_tracker.php.bak interface/patient_tracker/patient_tracker.php
cp library/globals.inc.php.bak library/globals.inc.php
```

## What it does

- Every Flow Board column header is clickable; click to sort, click again to
  reverse (▲/▼ indicator). Sorting is client-side and survives the auto-refresh.
- Computed columns (Arrive Time, Current-status elapsed, Total Time, Check Out
  Time) sort correctly via per-cell normalized sort values.
- First-open sort is set by the new globals (site default) with per-user override.

Verified against a stock 8.0.0 tree: patch applies with zero fuzz and
reconstructs the tested build byte-for-byte; `php -l` clean on both files.
