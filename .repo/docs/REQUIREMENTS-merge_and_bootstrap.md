# Requirements for Landing Changes, Bootstrapping Repositories, and Key Lifecycle
> - _github: [openintegrityproject-dev/.repo/docs/REQUIREMENTS-merge_and_bootstrap.md](https://github.com/OpenIntegrityProject/openintegrityproject-dev/blob/main/.repo/docs/REQUIREMENTS-merge_and_bootstrap.md)_
> - _Updated: 2026-10-03 by Christopher Allen <ChristopherA@LifeWithAlacrity.com>_

[![License](https://img.shields.io/badge/License-BSD_2--Clause--Patent-blue.svg)](https://spdx.org/licenses/BSD-2-Clause-Patent.html)
[![Project Status: WIP](https://www.repostatus.org/badges/latest/wip.svg)](https://www.repostatus.org/#wip)

This document applies to:

> - [`.repo/scripts/merge_pr.sh`](../scripts/merge_pr.sh) and [`.repo/scripts/bootstrap_oi_repo.sh`](../scripts/bootstrap_oi_repo.sh), version 0.1.00
> - Regression test: [`.repo/scripts/tests/TEST-bootstrap_oi_repo.sh`](../scripts/tests/TEST-bootstrap_oi_repo.sh)
> - Decisions and phases: [PLAN-oi_demo_bootstrap.md](PLAN-oi_demo_bootstrap.md)
> - Signature rules these scripts must satisfy: [REQUIREMENTS-verify_commit_signatures.md](REQUIREMENTS-verify_commit_signatures.md)

Each requirement is marked *(Required)*, *(Recommended)*, or *(Not yet met)*. Several come from mistakes made while landing changes by hand on 2026-10-02; those are noted.

## Landing Changes on `main`

### Process

- **M1 One path to `main`.** *(Required)* Every change reaches `main` as a merge commit signed by a main signer, pushed first to `staging/main`, and moved to `main` only after the `verify` check passes on that exact commit. *(Not yet met in this repository, which has landed changes by hand from a branch rather than through PRs; adopt `merge_pr.sh` from the first PR onward.)*
- **M2 Through a pull request.** *(Required)* Agent work is landed from an open PR, so the change, its CI results, and review comments are recorded on GitHub.
- **M3 Never GitHub's merge.** *(Required)* `gh pr merge` and the web UI's merge button are not used: they create commits signed by GitHub's key. GitHub marks the PR merged once its head is on `main`.
- **M4 The human's signature is the approval.** *(Required)* The merge commit is signed with a Secure Enclave key; the Touch ID prompt is the approval step. Agents never run `merge_pr.sh`.

### `merge_pr.sh` Behavior

- **M5 Verify before merging.** *(Required)* Fetch `pull/<n>/head`, confirm it matches the PR's reported head, and run the verifier on it with `--protected origin/main`. Refuse to merge a PR that does not verify.
- **M6 Show what is approved.** *(Required)* Print the commits and the diff summary, and ask for confirmation unless `--yes`.
- **M7 Verify the merge itself.** *(Required)* After merging locally, verify with `--protected HEAD`; discard the merge if it fails.
- **M8 Fail closed at every step.** *(Required)* Each step runs only if the one before it succeeded. *(Learned: a hand-typed chain whose merge line was not joined with `&&` ran its pushes after the merge failed.)*
- **M9 Wait on the exact commit.** *(Required)* Find the CI run by the merge commit's SHA (`gh run list --commit`), not "the latest run on `staging/main`", which may belong to an earlier commit. Give up after a bounded wait without moving `main`. *(Learned: the latest-run shortcut once watched a previous, already-green run.)*
- **M10 Leave a recoverable state.** *(Required)* If CI fails, `main` is untouched and the script says how to discard the local merge. If a merge stops half-way, abort it (`git merge --abort`) before retrying. *(Learned: a failed signing left `MERGE_HEAD` behind.)*
- **M11 No local edits in flight.** *(Required)* Refuse to run with uncommitted changes to tracked files.

### `staging/main`

- **M12** *(Required)* `staging/main` is unprotected, overwritten (force-pushed) by each landing, and never merged from. It exists only so `verify` can run on a commit before `main` moves to it.
- **M13** *(Not yet met)* Two landings must not race: the second must notice that `staging/main` moved, or that `main` moved under it, and stop. Today a human lands one PR at a time.
- **M14** *(Recommended)* Who may push to `staging/*` is unrestricted. A bad push there cannot reach `main` (the verifier runs `--protected HEAD` on it), but a ruleset limiting `staging/*` to admins would remove the noise.
- **M16 The ruleset bypass message is expected.** *(Note)* Moving `main` prints `remote: Bypassed rule violations for refs/heads/main: Cannot update this protected ref.` on every landing. It means the human's admin account bypassed the `main` ruleset, which is how `merge_pr.sh` moves `main`; it is not a failure. It also means landing depends on admin credentials, which is part of why A2 in [REQUIREMENTS-agent_sessions.md](REQUIREMENTS-agent_sessions.md) matters.

### Branch Ownership

- **M15** *(Recommended)* Each agent works on its own `claude/*` branch. When another session or agent adds commits to a branch it did not create (as happened on `oi-demo` PR #1), it fetches first, adds commits on top, never force-pushes, and says so on the PR.

## Bootstrapping a Repository

- **B1 Human key is hardware-backed.** *(Required)* The inception and human keys must be Secure Enclave (`sk-ecdsa-sha2-nistp256@openssh.com`) keys; others are refused unless overridden for testing.
- **B2 Device keys too.** *(Required)* Keys passed with `--device` become main and tag signers, so they must also be Secure Enclave keys. *(Learned: a software key from another device was nearly approved as a main signer.)*
- **B3 One commit per trust step.** *(Required)* Inception; human signer; other devices; local agent; cloud agent; main and tag roles; tooling. Each is signed by the human key and must verify under the rules as they stand after the previous commit.
- **B4 Resumable and previewable.** *(Required)* Completed steps are detected and skipped; `--dry-run` changes nothing and shows every command and file change.
- **B5 Stop before committing on any input problem.** *(Required)* All keys are checked, and the agent key created or found, before the first commit.
- **B6 Never write a partial key file.** *(Required)* Public keys are written to a temporary file and moved into place. *(Learned: a failed lookup left an empty `.pub` file.)*
- **B7 Create the agent key the way human keys are made.** *(Required)* Reuse an existing Secure Enclave identity with the same label; otherwise create it with `sc_auth create-ctk-identity -k p-256-ne -t none`; export its handle with `ssh-keygen -K`; save the stub in `~/.ssh` and the `.pub` beside the human key; load it with `ssh-add -S` (see F8). *(Implemented in 910b824 after the first real run; not yet exercised end to end on macOS.)*
- **B8 Agent keys are not GitHub account keys.** *(Required)* The bootstrap never registers agent keys with any GitHub account (see F9).
- **B9 Protect `main` immediately.** *(Required)* After the first push, create both rulesets from the verifier requirements. The repository must be public, or on a paid plan, for rulesets to apply.
- **B10 Local agent signing config stays local.** *(Required)* `.claude/settings.local.json` sets the agent's signing key for Claude Code's processes only and is Git-ignored.
- **B11** *(Not yet met)* Run `core`'s `audit_inception_commit-POC.sh` on the new repository as a final step, once compatibility is confirmed (see the verifier requirements' open questions).
- **B12 Tests never reach GitHub.** *(Required)* `TEST-bootstrap_oi_repo.sh` runs the scripts in child zsh processes with a stub `gh`. It sets `ZDOTDIR` to its test root so the user's `~/.zshenv` cannot put the real `gh` ahead of the stub, and refuses to run any test unless a child zsh resolves `gh` to the stub. *(Learned: on a Mac whose `~/.zshenv` prepends `/opt/homebrew/bin`, the test called real GitHub and tried to create `test/oi-demo`.)*

## Key Lifecycle

- **K1 Key file locations.** *(Required)* Public keys live in one directory per machine (`~/.keys` on chryseikori); Secure Enclave stubs live in `~/.ssh` with mode 600. Each repository's `user.signingkey` names the `.pub` file, so moving it breaks signing until every repository's setting is updated. *(Learned on 2026-10-02.)*
- **K2 Agent availability after reboot.** *(Required)* Human and agent stubs must be re-added with `ssh-add -S` after logout or reboot; before handing work to local Claude Code, check that `ssh-add -L` lists its key. Before any step that signs with a human key, confirm someone is at the Mac: an unanswered Touch ID prompt yields an invalid commit rather than an error (F10).
- **K3 Rotation.** *(Not yet met)* Secure Enclave identities carry one-year validity: chryseikori 2027-05-07, athena 2027-04-16, seshat 2027-03-21, local agent 2027-10-02 (F5). A rotation ceremony is needed: create the new key, approve it in all three signers files in a commit signed by a current main signer, prove possession with one commit from the new key, then remove or `valid-before`-limit the old key. Set `valid-before` on each entry to its identity's expiry.
- **K4 Proof of possession.** *(Not yet met)* A newly approved device key should make one commit before it may sign `main` or tags. The verifier does not yet enforce this.
- **K5 Revocation.** *(Not yet met)* Removing a key stops future commits but leaves its past commits valid. Define whether a compromised key needs a dated revocation that also invalidates earlier commits after a given time.
- **K6 Global versus repository signing keys.** *(Recommended)* Repositories set `user.signingkey` locally; the global setting (still athena's software key) is left alone until other projects move to Secure Enclave keys.

## Signing-Environment Reports

- **E1** *(Required)* `collect_signing_environment.sh` reads only public information. Its reports go to Git-ignored `.repo/reports/` and are reviewed before being shared, because they contain host names, key comments, and home-directory paths.
