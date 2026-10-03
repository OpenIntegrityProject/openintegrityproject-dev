# CLAUDE.md

This is the Open Integrity Project's development repository. Every commit must be SSH-signed by a key listed in `.repo/config/verification/`, and CI checks every commit and tag with `.repo/scripts/verify_commit_signatures.sh`. Requirements are in `.repo/docs/`; read `REQUIREMENTS-agent_sessions.md` before changing anything under `.claude/`.

- Work only on `claude/*` branches. Never push to `main` or `staging/*`.
- Never edit files in `.repo/config/verification/`; the verifier rejects agent changes to them.
- Before pushing, run `zsh .repo/scripts/verify_commit_signatures.sh --protected origin/main`, `zsh .repo/scripts/tests/TEST-verify_commit_signatures.sh`, and `zsh .repo/scripts/tests/TEST-bootstrap_oi_repo.sh`.
- Open a pull request. A human merges with `.repo/scripts/merge_pr.sh <number>`, signing the merge with a Secure Enclave key; never use `gh pr merge`.
- Repository scripts follow the zsh conventions of `OpenIntegrityProject/core`.

## Why `.claude/settings.json` denies push, merge, and admin commands

Local Claude Code sessions run with the human's own GitHub credentials, which have admin rights here, so a mistaken `git push`, `gh api` call, ruleset edit, or use of `gh auth token` would succeed with full authority. The deny rules catch common forms of these mistakes; they are not a security boundary. The real guards are the GitHub rulesets on `main` and the signature verifier.
