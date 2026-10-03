# PRD: Human and Agent Workflow for Open Integrity Repositories
> - _github: [openintegrityproject-dev/.repo/docs/PRD-human_agent_workflow.md](https://github.com/OpenIntegrityProject/openintegrityproject-dev/blob/main/.repo/docs/PRD-human_agent_workflow.md)_
> - _Draft: 2026-10-03, prepared by Claude Code for review by Christopher Allen_

[![License](https://img.shields.io/badge/License-BSD_2--Clause--Patent-blue.svg)](https://spdx.org/licenses/BSD-2-Clause-Patent.html)
[![Project Status: WIP](https://www.repostatus.org/badges/latest/wip.svg)](https://www.repostatus.org/#wip)

This document defines how a human and Claude Code agents, local and cloud, work together in an Open Integrity repository: who does what, on which branch, how they hand work to each other, how `main` records what each pull request did, and what enforces the rules. It replaces the ad hoc process used for `oi-demo` PR #1, whose lessons are recorded at the end and whose reviews are kept in [RECORD-oi_demo_pr1_reviews.md](RECORD-oi_demo_pr1_reviews.md).

It builds on the [verifier requirements](REQUIREMENTS-verify_commit_signatures.md) (trust model, rules R1 to R7, the staging flow) and the [`oi-demo` bootstrap plan](PLAN-oi_demo_bootstrap.md) (keys and signers). Nothing here changes those rules.

## Problem: Three Sessions Shared One Branch Without a Protocol

`oi-demo` PR #1 set out to add a `.claude/settings.json`. It took three review rounds in one day across three Claude Code sessions and grew a 436-line client-side push guard. The work itself was sound. The process around it was not:

- **No roles.** A local session on chryseikori reviewed, a cloud session fixed rounds 1 and 2, and a second local session on the same Mac wrote round 3. All three committed to, or were asked to commit to, `claude/happy-allen-7uvlxs`.
- **The human was the message bus.** Each session's output was pasted into another by hand. Prompts written for one session were pasted into another, twice, and a fixer was given a reviewer's prompt.
- **Session state was lost on restart.** Each restart (needed to reload `.claude/settings.json`) erased the session's context. A gitignored `CLAUDE.local.md` was added as a workaround.
- **The guard was unbounded work.** A hook that reads command text can always be evaded by another spelling. Each review round found more, and the cloud session's safety classifier stopped it three times while it wrote or reviewed push probes.
- **`main` loses the branch's story.** `merge_pr.sh` writes `Merge pull request #N from <ref>` and the PR title. Recent merges here record even less: `cb1c8d8` says only "Merge agent key export from Claude". The PR description, the review rounds and the per-commit signers are not in `main`.

## Goals

- **G1** Every change reaches `main` through a human-signed merge commit that records the PR's description, its commits and their signers.
- **G2** Each session has one role on one branch. Work passes between sessions through the pull request, not through a person copying prompts.
- **G3** Agents cannot move `main`, change trust files, merge, or change repository settings. GitHub and credentials enforce this, not client-side hooks.
- **G4** A session can stop and restart at any point and resume from the pull request alone.
- **G5** Local and cloud agents follow the same workflow.

## Non-Goals

- Stopping a malicious agent that holds the human's admin credentials. G3 removes those credentials from agent environments instead.
- Release branches, `develop`, or other full git-flow structure. These wait until the project ships releases.
- Client-side command parsing as a security control.

## Actors and Keys Stay as the Verifier Defines Them

| Actor | Key | Signs | Listed in |
|---|---|---|---|
| Human | Secure Enclave, Touch ID (`@ChristopherA/<device>-se`) | Merges to `main`, tags, trust-file changes | all three signers files |
| Local agent | Secure Enclave, no Touch ID (`@claude-local/<device>`) | Commits on its own branches | `allowed_commit_signers` |
| Cloud agent | Anthropic-held ed25519 (`@claude-code-web`, see F6) | Commits on its own branches | `allowed_commit_signers` |

## Roles: One Session, One Job

A role belongs to a session for the life of a pull request. The human assigns it when starting the session.

| Role | Holds | May | May not |
|---|---|---|---|
| **Implementer** | One branch | Commit and push to its branch; reply to reviews | Push to any other branch; merge |
| **Reviewer** | Nothing | Read; run tests and probes in scratch repositories; post review comments | Commit or push to the branch under review |
| **Integrator** (human) | `main` | Merge with `merge_pr.sh`; reassign roles | |

- **W1 One implementer per branch.** A second session that needs to change a branch opens its own branch from it and a pull request into it. The human may reassign the implementer role, and the reassignment is recorded as a PR comment.
- **W2 Reviewers do not push.** Findings go to the pull request as a review comment in the status format below.
- **W3 The implementer answers every review round** on the pull request: fixed (with commit), declined (with reason), or deferred (with issue link).
- **W4 Sessions are pointed at pull requests, not given pasted prompts.** The human's instruction to any session is "Act as <role> on <PR URL>." Everything else the session needs is on the PR.
- **W5 A role session starts by reading the PR**: description, latest status comment, and unresolved review threads.

## Coordination: The Pull Request Is the Message Bus

Every role ends each turn of work with one status comment on the PR. The latest status comment is the state of the PR; G4 depends on nothing else.

```markdown
### Status: needs-review

- **Role:** implementer
- **Session:** https://claude.ai/code/session_…
- **Head:** 2dbc6c9
- **Done:** fixed round 2 items 1–4; 175 of 175 guard tests pass
- **Next:** reviewer: verify round 2 repros; check over-blocking
- **Open:** `git checkout main; echo $(git push)` allowed (deferred, #12)
```

| Status | Next owner |
|---|---|
| `needs-review` | Reviewer |
| `needs-fix` | Implementer |
| `ready-to-merge` | Integrator |
| `blocked` | Named in the comment |

- **C1** The status line is the first line, so it is readable in notifications and `gh pr view`.
- **C2** `CLAUDE.local.md` remains for per-device notes, but it is not the coordination record.
- **C3** Review comments use the same block, with findings ranked by how likely an agent is to hit them by mistake, each with a minimal reproduction.

## Branch Model: Named Topic Branches and One Integration Path

| Branch | Written by | Purpose |
|---|---|---|
| `main` | Human only, by `merge_pr.sh` | First-parent chain of human-signed merges (R4) |
| `staging/main` | Human only, by `merge_pr.sh` | Where a merge is checked by `verify` before `main` moves to it |
| `claude/<topic>` | One agent implementer | Agent work for one pull request |
| `human/<topic>` | The human | Human work for one pull request |
| `claude/<topic>--<subtopic>` | A second implementer | Work stacked on another branch; its PR targets that branch |

- **B1** Pull requests target `main`, or another topic branch when stacked.
- **B2** Merges are merge commits (`--no-ff`). Squash and rebase merges are not used: they discard the agents' signed commits, which are the record Open Integrity exists to keep.
- **B3** Topic branches are deleted after merge. Their commits remain reachable from `main` through the merge's second parent.
- **B4** Branch names come from the topic, not from the session (not `claude/happy-allen-7uvlxs`), so the name means something in the merge record.

## Merge Commits Record the Branch

`merge_pr.sh` writes the merge commit message from the pull request and the verifier's output:

```text
Merge #1: Add Claude Code deny rules and zsh SessionStart hook

<PR description, verbatim>

Commits (claude/settings-json; abridged):
  1fadc72 @claude-code-web     Add Claude Code deny rules and zsh SessionStart hook
  b7d8267 @claude-code-web     Make zsh hook never hang or fail; soften CLAUDE.md claim
  c76b504 @claude-local/chryseikori  Block pushes whose branch or config changes before the push

PR: https://github.com/OpenIntegrityProject/oi-demo/pull/1
Co-Authored-By: Claude <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_…
Signed-off-by: Christopher Allen <ChristopherA@LifeWithAlacrity.com>
```

- **M1** The subject is `Merge #<N>: <PR title>`.
- **M2** The body carries the PR description as it stands at merge. `merge_pr.sh` shows it and asks for confirmation, so an outdated description is caught before signing.
- **M3** A `Commits` section lists each commit in the merged range with its short ID, the principal from the verifier, and its subject.
- **M4** Trailers from the merged commits (`Co-Authored-By`, `Claude-Session`) are collected, deduplicated, and appended before `Signed-off-by`.
- **M5** `git log --first-parent main` then reads as one entry per pull request, and `git log main^2` on any merge shows the branch's own commits.

## Enforcement: GitHub and Credentials, Not Client Hooks

The server already stops the worst case. R4 requires a human Secure Enclave signature on every commit in `main`'s first-parent chain, and the `main` rulesets require `verify` to pass before `main` moves. An agent push to `main` therefore fails `verify` whatever command produced it. The remaining exposure is what an agent can do with the human's admin credentials: change rulesets, delete branches, edit settings.

- **E1** Agents use a GitHub identity without admin rights. Local agents authenticate as that identity for both `git push` and `gh`, configured in `.claude/settings.local.json` alongside the agent signing key.
- **E2** A ruleset limits that identity to creating and updating `claude/*`. `main`, `staging/*` and `human/*` are writable only by the human.
- **E3** The verifier in CI stays authoritative for signatures and trust files (R3, R4).
- **E4** `.claude/settings.json` keeps a short deny list (`gh pr merge`, `merge_pr.sh`, admin `gh` commands) as a convenience that saves a round trip. It has no command-parsing hook.
- **E5** Controls are tested by configuration, not by adversarial probing. A server-side rule is checked by attempting the forbidden action once as the agent identity; it needs no catalogue of command spellings.

## Local and Cloud Agents Share One Workflow

- **A1** Both read the same `CLAUDE.md`, which states the roles (W1 to W5), the status format (C1 to C3) and the branch rules (B1 to B4).
- **A2** Cloud environments install `zsh` and `openssh-client` in the environment setup script, so the verifier runs before every push.
- **A3** Agents never merge. Only the human runs `merge_pr.sh`, on a device holding a Secure Enclave key.
- **A4** Either kind of agent may hold either agent role. The human picks per pull request.

## Environment Findings Shape the Setup

Established while building `oi-demo` PR #1 on 2026-10-02:

- **EF1 The cloud image lacks `zsh` and `ssh-keygen`.** The verifier needs both. A SessionStart hook installs `zsh`; `openssh-client` belongs in the environment setup script (A2).
- **EF2 `apt-get install zsh` hangs in the cloud image.** A pre-existing `/etc/zsh/zshrc` triggers a dpkg config-file prompt, and dpkg waits on stdin. The template hook passes `--force-confdef --force-confold`, reads stdin from `/dev/null`, uses `sudo -n`, and always exits 0 with a warning on stdout.
- **EF3 A restart to pick up settings costs the session its memory.** In the cloud session, a PreToolUse hook added to `.claude/settings.json` took effect on the next tool call. The local sessions were restarted after each settings change to be sure, and each restarted session had no memory of the previous one. This is why G4 puts the state on the pull request.
- **EF4 Bash deny rules match command text.** They are not a security boundary (Claude Code permissions documentation). A path rule anchors to the project root only with a leading `/`; a bare path is relative to the session's working directory. A deny rule wins over an allow at every settings level.
- **EF5 `gh pr view` does not work in cloud sessions**, which cannot reach GitHub's GraphQL API, and `gh api` is on the template deny list. Sessions read pull requests through the GitHub tools instead.
- **EF6 Writing evasion probes trips the cloud safety classifier.** Three attempts to test or review the push guard were stopped. This supports E5.

The templates are in [`.repo/templates/oi-repo/.claude/`](../templates/oi-repo/.claude/): `settings.json` (the E4 deny list and the SessionStart hook) and `hooks/install-zsh.sh`.

## Lessons from `oi-demo` PR #1

| Observation | Requirement |
|---|---|
| Three sessions committed to one branch; prompts reached the wrong session | W1, W4 |
| Restarts lost session context | G4, C1 |
| The human copied every handoff by hand | Coordination via status comments |
| A client-side guard grew to 436 lines and stayed incomplete | E1, E2, E4 |
| Testing that guard tripped the cloud safety classifier | E5 |
| Merge commits recorded only a title | M1 to M5 |
| Session-named branches meant nothing in `main` | B4 |
| `gh api` was denied by the PR's own rules, and `gh pr view` needs GraphQL, which cloud sessions can't reach, so a session could not read PR comments with `gh` | Sessions read PRs through the GitHub tools (EF5) |

## Rollout

### Phase 0: This Document (Claude, then Christopher)

- [ ] Review and merge this PRD.

### Phase 1: Merge Record (Claude)

- [ ] `merge_pr.sh`: M1 to M5, with `--dry-run` printing the message.
- [ ] `TEST-bootstrap_oi_repo.sh`: assert the merge message format against the stub `gh`.

### Phase 2: Agent Identity and Rulesets (Christopher)

- [ ] Create the agent GitHub identity (see open questions) and the `claude/*` ruleset (E1, E2).
- [ ] Attempt one push to `main` and one ruleset change as the agent identity; record both refusals (E5).

### Phase 3: Protocol in the Repository (Claude)

- [ ] `CLAUDE.md` text for A1, and the status comment template (C1 to C3).
- [ ] Add `bootstrap_oi_repo.sh` support for copying the templates in `.repo/templates/oi-repo/` into a new repository.

### Phase 4: Apply to `oi-demo` (Claude, then Christopher)

- [ ] Close `oi-demo` PR #1 with a link to this document. Its review comments are captured in [RECORD-oi_demo_pr1_reviews.md](RECORD-oi_demo_pr1_reviews.md), and its push guard in [`.repo/archive/guard-git-push/`](../archive/guard-git-push/).
- [ ] Open a new PR on a topic branch with the templates from `.repo/templates/oi-repo/.claude/` and the `CLAUDE.md` protocol.

## Open Questions

- **Agent identity for local sessions:** a second GitHub account, a fine-grained personal access token, or a GitHub App installation. A token is simplest; an App is revocable per repository and does not consume a seat.
- **Cloud push identity:** cloud sessions push through the Claude GitHub App on the human's behalf. Confirm which actor GitHub records, and whether E2's ruleset can name it.
- **Verifier check for M1 to M5:** whether `verify` should fail a merge on `main` whose message lacks the `Commits` section, or only report it.
- **Stacked branches:** whether `--` in branch names (B-table) is enough, or stacked work needs its own prefix.
- **Scope of the cloud signing key** (F6), which affects how much a `@claude-code-web` signature proves in M3.
