# Plan: Bootstrapping the `oi-demo` Repository
> - _Updated: 2026-10-03 by Christopher Allen <ChristopherA@LifeWithAlacrity.com>_

`OpenIntegrityProject/oi-demo` will be a public demonstration of an Open Integrity repository in which humans and Claude Code agents work under signing rules recorded in the repository itself. A local script does only the steps that need the human's Secure Enclave key or admin rights. Everything after that arrives as Claude pull requests, which the human approves by signing the merge with Touch ID.

## Decisions

- **Human keys** are Secure Enclave keys with Touch ID (`sc_auth create-ctk-identity -k p-256-ne -t bio`): chryseikori (inception), seshat, and athena.
- **The local Claude Code key** is also a Secure Enclave key, but without Touch ID (`-t none`). It cannot be copied off the Mac, and it signs without a prompt. Its role, not its storage, marks it as an agent: it is listed only in `allowed_commit_signers`.
- **The Claude Code on the web key** is Anthropic's (see F6 in the [verifier requirements](REQUIREMENTS-verify_commit_signatures.md)). It is also listed only in `allowed_commit_signers`.
- **Agent keys are not added to anyone's GitHub account.** GitHub would otherwise show agent commits as "Verified" for that person. Trust comes from the repository's signers files.
- **One clone, two signers.** The script writes `.claude/settings.local.json` (ignored by Git) so local Claude Code's processes sign with the agent key through `GIT_CONFIG_*` environment variables, while the human's terminal keeps signing with Touch ID.
- **PRs are merged with `merge_pr.sh`, never `gh pr merge`**, which produces commits signed by GitHub's key.
- The repository is **public**.

## Phase 0: Build and Test (Claude, in `openintegrityproject-dev`)

- [x] `.repo/scripts/bootstrap_oi_repo.sh`: resumable steps, `--dry-run`, and refuses a non-Secure-Enclave human key unless told otherwise.
- [x] `.repo/scripts/merge_pr.sh`: verify the PR's commits, show them, merge with Touch ID, push to `staging/main`, wait for `verify`, move `main`.
- [x] `.repo/scripts/tests/TEST-bootstrap_oi_repo.sh`: runs both scripts end to end with throwaway keys, a local bare repository standing in for GitHub, and a stub `gh`.

Not testable outside macOS, and so first exercised in Phase 1: creating the agent key. The first real run showed that `sc_auth` creates no SSH key handle (finding F8); the key was finished by hand with `ssh-keygen -K` and `ssh-add -S`, and `--create-agent-key` now does the same (910b824).

## Phase 1: Run on chryseikori (Christopher)

Prerequisite: each other device's Secure Enclave **signing** public key (`sign_se_*.pub`), copied to chryseikori.

```sh
.repo/scripts/bootstrap_oi_repo.sh --dry-run --create-agent-key \
    --device seshat=<path>/sign_se_ecdsa-seshat.pub \
    --device athena=<path>/sign_se_ecdsa-athena.pub
```

Then run the same command without `--dry-run`. It creates `../oi-demo` with these commits, each signed with chryseikori's Secure Enclave key (one Touch ID prompt each):

| # | Commit | Effect |
|---|---|---|
| 1 | Inception | Empty commit; committer is the key's fingerprint |
| 2 | Human signer | `@ChristopherA/chryseikori-se` in `allowed_commit_signers` |
| 3 | Devices | `@ChristopherA/seshat-se` and `@ChristopherA/athena-se` |
| 4 | Local agent | `@claude-local/chryseikori` |
| 5 | Cloud agent | `@claude-code-web`, with the scope caveat in the commit message |
| 6 | Roles | `allowed_main_signers` and `allowed_tag_signers`: the three Secure Enclave keys |
| 7 | Tooling | Verifier, tests, `merge_pr.sh`, CI workflow, README, `CLAUDE.md`, `.gitignore` |

It then verifies the result, creates the public GitHub repository, pushes `main`, and adds the two `main` rulesets. Re-running skips finished steps.

**Manual step:** install the Claude GitHub App on `oi-demo`: <https://github.com/apps/claude/installations/select_target>.

**Status (2026-10-03):** done. `oi-demo` was created with seven commits signed by chryseikori's Secure Enclave key, all verified; CI passed and both rulesets are active; the Claude GitHub App is installed.

## Phase 2: Each Other Device (Christopher)

On seshat and athena: clone `oi-demo`, set `user.signingkey` to that device's Secure Enclave key, and make one small signed commit through a PR. This proves the device holds the key approved in commit 3.

## Phase 3: Claude Pull Requests (Claude, cloud or local)

1. `.claude/settings.json` shared by local and cloud sessions: permissions to run the verifier and tests, and a SessionStart hook that installs zsh in cloud sessions.
2. README badges and a "Verify in your browser" link.
3. In-browser verifier on GitHub Pages.

Each is merged with `merge_pr.sh <number>`.

**Status (2026-10-03):** step 1 is `oi-demo` PR #1 (deny rules, zsh hook, a push guard), with commits from both cloud and local Claude that all verify. Review follow-ups are `oi-demo` issues #3 (deny `gh auth token`, fixed on the PR branch), #4 (shrink the push guard), and #5 (record that the cloud key is shared across sessions).

## Open Items

Tracked as requirements: rotation (K3), proof of possession (K4), and revocation (K5) in [REQUIREMENTS-merge_and_bootstrap.md](REQUIREMENTS-merge_and_bootstrap.md); agent credentials (A2) in [REQUIREMENTS-agent_sessions.md](REQUIREMENTS-agent_sessions.md).
