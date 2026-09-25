# Triage Labels

The skills speak in terms of two category roles and five canonical state roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

## Category roles

| Canonical role | Tracker label | Meaning |
| --- | --- | --- |
| `bug` | `bug` | Requested behavior is broken |
| `enhancement` | `enhancement` | New behavior or improvement |

## State roles

| Canonical role | Tracker label | Meaning |
| --- | --- | --- |
| `needs-triage` | `needs-triage` | Maintainer needs to evaluate this issue |
| `needs-info` | `needs-info` | Waiting on reporter for more information |
| `ready-for-agent` | `ready-for-agent` | Fully specified and ready for an AFK agent |
| `ready-for-human` | `ready-for-human` | Requires human implementation |
| `wontfix` | `wontfix` | Will not be actioned |

Every triaged issue or in-scope pull request has exactly one category label and one state label. State labels are mutually exclusive. When a skill mentions a canonical role, use its mapped tracker label.
