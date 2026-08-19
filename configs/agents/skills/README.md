# Shared agent skills

One skill per subdirectory, each containing a `SKILL.md`. Every subdirectory
here is symlinked into the skills directory of each enabled agent harness
(claude-code, codex, opencode) by `modules/tools/agent-skills.nix`.

## Format

`SKILL.md` starts with YAML frontmatter carrying the two fields every harness
understands, then plain markdown instructions:

```markdown
---
name: my-skill
description: One line telling the agent when to load this skill.
---

The instructions.
```

Harness-specific frontmatter (claude's `allowed-tools`, `model`, …) is ignored
by the others, so keep it out of shared skills; a skill that genuinely needs it
belongs in that harness's own config dir instead.

Skill directories may hold extra files (scripts, references) alongside
`SKILL.md` — the whole directory is linked, so relative paths inside it resolve.

## Editing

The symlinks point at this working copy, not at a `/nix/store` copy, so edits to
an existing skill take effect on the next agent launch with no rebuild. Only the
*set* of skill names is baked in at eval time: run `nix-rebuild` after adding,
renaming, or removing a skill directory.

Note for codex: it refuses to follow a symlinked `SKILL.md`, only a symlinked
skill *directory* (openai/codex#10470). That is what this module links, so it
works — but don't restructure it into per-file links.
