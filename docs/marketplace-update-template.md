# Marketplace update request

Ready to submit after the pull request is merged. Replace `MERGED_MAIN_SHA` with
the full current `main` SHA. The marketplace rejects a feature-branch SHA that
is not the repository's current HEAD. Maintainer approval is required before
this replaces the live listing.

Issue title: `[Verify]: File Shelf 0.4.0, fixes and desktop preview`

## Issue body

### Verification action

Verify and publish a newer upstream commit

### Plugin ID

kigojomo.file-shelf

### Repository URL

https://github.com/KigoJomo/file-shelf

### Target commit

MERGED_MAIN_SHA

### Verification acknowledgment

- [x] I understand that only the exact target commit can become a verified marketplace snapshot and that verification is not a security audit.

### Update details

File Shelf 0.4.0 fixes window ownership, launcher lock inheritance, shell-reload
state, queued command recovery, and dialog focus behavior. It replaces
continuous focus polling with compositor-event checks. The manifest includes a
fuller summary and the repository now has a root desktop preview plus two
additional README screenshots. Installation, optional keybindings, recovery,
upgrade behavior, limitations, and removal are documented.

Validation includes helper and service regression tests, Omarchy plugin
validation, and live checks on Omarchy 4.0.2 / Hyprland 0.56.2. See the repository
review report for tested behavior and hardware/UI limits.
