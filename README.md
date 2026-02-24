# Time Access Contract

A time-based permission control contract that restricts access to specific
functions or roles within defined time windows.

## Key Functions
- `grant-access` — Assign time-bound access to a principal
- `revoke-access` — Remove access before expiration
- `is-access-active` — Check if access is currently valid
- `set-access-window` — Configure start and end times
- `get-access-details` — Retrieve access configuration data

Designed for subscription systems, limited-time privileges, governance windows,
and scheduled protocol feature activation.
