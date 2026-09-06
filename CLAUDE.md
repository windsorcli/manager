# Windsor Manager — Claude Code Context

Skills are defined in `.claude/skills/` and are discovered automatically by Claude Code, Cursor, and other adopting tools.

## Non-negotiable rules

1. **Code comments** — describe current behavior and non-obvious constraints only. No issue/PR/ADR citations (`cli#3097`, `see ADR-0004`), no process or reasoning narrative ("this is what makes X possible"), no change history ("previously X, now Y"). If it wouldn't confuse a reader without the comment, don't write it. That reasoning belongs in the commit message or a docs/adr file, never in the code. **Hard cap: one line, ~15 words.** State the one non-obvious fact, not the chain of reasoning that led to it — no "and", "because X, so Y, which means Z" clause-chaining to smuggle in a second and third sentence. Two lines only if genuinely unavoidable, never three+. Match the comment density of the surrounding file. Before writing a comment, draft it, then cut it in half.

   Bad (multi-clause, explains history/reasoning):
   ```
   # nginx fronts every request but has no /metrics of its own, and the exporter's own
   # health checks talk to harbor-core directly, bypassing nginx entirely -- so
   # harbor_health/harbor_up both stay green even if nginx itself is down.
   ```
   Good (states the fact):
   ```
   # nginx has no /metrics; harbor_health/harbor_up don't reflect its state.
   ```

2. **The Core boundary** — follow `docs/adr/0001-layering-on-core.md`. Manager authors only what a fleet needs; a single-cluster capability belongs in Core. Turn Core capabilities on through context values, never redeclare a Core facet or schema key.

3. **Facet authoring** — follow `facet-author` for facet YAML structure, config layering, and `when:`/`requires:` conventions.

4. **Terraform style** — follow `terraform-style` and `terraform/STYLE.md`.

5. **Kustomize authoring** — follow `kustomize-author` and `kustomize/GUIDELINES.md` for timeout/interval rules and base/resources/components layering.

6. **Testing** — follow `windsor-test` for `.test.yaml` format. Run `task test` (or `windsor test` for blueprint-only) before considering work done.

7. **PRs** — use `create-pr` to push and open/update a PR, and `address-pr-feedback` to work through review comments and CI failures one finding at a time.

## Key commands

```
task test              # full suite: terraform, blueprint, kustomize builds, prometheus rules
windsor test            # blueprint facet tests only
task fmt                # terraform fmt check
task scan               # security scan
```
