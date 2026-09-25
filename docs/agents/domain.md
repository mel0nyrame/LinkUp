# Domain Docs

How the engineering skills consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in.

If these files don't exist, **proceed silently**. Don't flag their absence or suggest creating them upfront. The `/domain-modeling` skill creates them lazily when terms or decisions are actually resolved.

## File structure

This is a single-context repo:

```text
/
├── CONTEXT.md
├── docs/
│   ├── adr/
│   │   ├── 0001-example-decision.md
│   │   └── 0002-another-decision.md
│   └── agents/
└── lib/
```

## Use the glossary's vocabulary

When output names a domain concept—in an issue title, refactor proposal, hypothesis, or test—use the term defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If a needed concept isn't in the glossary, either the project already uses different language and the proposal should be reconsidered, or the glossary has a real gap worth recording through `/domain-modeling`.

## Flag ADR conflicts

If output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
