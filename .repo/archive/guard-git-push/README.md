# Rejected: Client-Side Git Push Guard

This is the PreToolUse hook built for `oi-demo` PR #1 (final version `2dbc6c9`, 2026-10-02), kept as a reference. It is **not used** by any repository. The [workflow PRD](../../docs/PRD-human_agent_workflow.md) replaces it with an agent GitHub identity and rulesets (EN1, EN2, EN4).

`guard-git-push.pl` read each Bash command an agent was about to run and blocked `git push` commands that forced or targeted `main` or `staging/*`, plus any run of `merge_pr.sh`. Three review rounds kept finding spellings it missed, because a hook that reads command text has to model the shell. The [review record](../../docs/RECORD-oi_demo_pr1_reviews.md) has the details.

The test suite is the useful part. Its 175 cases record which shell forms a text-based guard must handle: heredocs, quoting, `$'...'`, command substitution, line continuations, variables, aliases, `git -C`, `cd`, branch switches before a push, and push config. Run it with:

```sh
bash .repo/archive/guard-git-push/tests/TEST-guard-git-push.sh
```

Files:

- `guard-git-push.sh`: entry point; blocks push and merge commands if perl is missing
- `guard-git-push.pl`: the guard
- `tests/TEST-guard-git-push.sh`: 175 allow and block cases
