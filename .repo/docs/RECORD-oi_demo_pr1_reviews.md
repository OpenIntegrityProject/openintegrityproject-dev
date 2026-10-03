# Record: `oi-demo` PR #1 Reviews
> - _Captured: 2026-10-03 from [OpenIntegrityProject/oi-demo#1](https://github.com/OpenIntegrityProject/oi-demo/pull/1), so the record survives if `oi-demo` is deleted_

`oi-demo` PR #1 (branch `claude/happy-allen-7uvlxs`, final head `2dbc6c9`) added `.claude/settings.json` with permission deny rules, a SessionStart hook that installs zsh, and a PreToolUse guard for `git push`. It went through three review rounds on 2026-10-02 across three Claude Code sessions. This record keeps the review findings and replies, which are the evidence behind the lessons in the [workflow PRD](PRD-human_agent_workflow.md).

What came out of it:

- The SessionStart hook and the deny list are kept as templates in [`.repo/templates/oi-repo/.claude/`](../templates/oi-repo/.claude/).
- The push guard and its 175 tests are kept as a rejected reference in [`.repo/archive/guard-git-push/`](../archive/guard-git-push/).
- The process problems became the PRD's roles, status comments and enforcement requirements.

## Commits and Signers

| Commits | Signer | Session role |
|---|---|---|
| `1fadc72` to `6335160` | `@claude-code-web` | Cloud session: initial PR and fixes for rounds 1 and 2 |
| `c76b504`, `2dbc6c9` | `@claude-local/chryseikori` | Second local session: round 3 fixes |
| (none) | | First local session: reviewer for rounds 1 and 2 |

## Round 1 Review (local session, `1fadc72`)

Relayed to the cloud session in chat, not posted to the PR. Four findings, all fixed in `b7d8267` and `8b904fd`:

1. **High:** `Bash(git push --force*)` and `Bash(git push -f*)` matched only when the flag came right after `push`, so `git push origin x --force` and `--force-with-lease` got through.
2. **Medium:** pushes to `main` in other refspec forms (`main:main`, `+main`, `HEAD:main --no-verify`, `x:staging/foo`) matched none of the deny patterns.
3. **Medium:** `Edit(.repo/config/verification/**)` was relative to the working directory, not the project root. Fixed by anchoring with a leading `/`.
4. **Medium:** `install-zsh.sh` used plain `sudo`, which could hang on a password prompt or fail session start under `set -e`. Fixed with `sudo -n` and a warning that always exits 0.

A follow-up local review of `8b904fd` found more evasions (line continuations, `if`/`!`/loops, variables, `heads/main`, glob refspecs, `git -C`, `<<<`, `sudo -u`, quoting, aliases, `merge_pr.sh` spellings, fail-open when perl is missing), fixed in `2ac550b`. A second pass on `408b849` found substitutions, variable subcommands, `-c alias.*`, `$'...'`, `eval`, `send-pack`, and a heredoc over-block, fixed in `6335160`.

## Round 2 Review (local session, `6335160`)

Posted to the PR by the reviewer session. Sections 3 and 4 are condensed; the rest is verbatim:

> All six round-1 bypasses are now blocked, the quoted-heredoc-with-trailing-backslash case is allowed again, and `TEST-guard-git-push.sh` passes 106 of 106. I tested each new case two ways: I fed it to `guard-git-push.sh` as hook JSON, then ran the ones the hook allowed for real against a throwaway bare origin to see whether `main` moved. None of these are regressions: the 408b849 hook allows every one of them too.
>
> ### 1. Switching branches before the push (high)
>
> This is the one I'd expect an agent to hit by mistake:
>
> ```sh
> git checkout main && git merge --ff-only claude/x && git push
> git checkout main && git merge --ff-only claude/x && git push origin HEAD
> git switch main; git push origin @
> ```
>
> The hook looks up the current branch when it runs, which is before the checkout, so `HEAD`, `@` and the no-refspec case all resolve to `claude/x`. All three moved `main`. The deny rules in `.claude/settings.json` don't catch it either: I ran the second form through a local Claude Code session against the scratch origin, and it pushed.
>
> ### 2. Config that picks the destination (medium)
>
> ```sh
> git -c push.default=upstream push
> git -c remote.origin.push=HEAD:main push origin
> git -c remote.origin.push=HEAD:main push
> git config remote.origin.push HEAD:main && git push
> ```
>
> The hook reads `-c alias.*` and ignores every other `-c` key, and it never consults `push.default` or `remote.<name>.push`. The `push.default=upstream` case matters because `git checkout -b claude/x origin/main` sets the upstream to `origin/main`, so a bare `git push` under that setting goes to `main`. All four moved `main`.
>
> ### 3. Wrappers missing from the prefix list (low)
>
> `arch -arm64`, `xcrun`, `caffeinate -i`, `script -q /dev/null`, `find . -exec`, and `tcsh -c`/`csh -c` in front of a push to `main`. Each moved `main`.
>
> ### 4. Parser edges (low)
>
> Deliberate-evasion shapes rather than mistakes: nested parentheses in `$( (echo main) )`, a `'` inside double quotes swallowing a later `$(`, `--config-env=alias.p=P`, an uppercase `-c alias.P` (git lowercases alias keys), and a fake heredoc opener (`echo '<<EOF'` or `# <<EOF`) hiding the next line.
>
> ### Over-blocking
>
> - `git push origin "claude/$(date +%Y%m%d)-fix"` is newly blocked in 6335160. That's expected, since only the current-branch substitutions are resolved, and it fails closed.
> - Already blocked at 408b849, and the most likely for an agent to hit: a multi-line `git commit -m "..."` or `gh pr create --body "..."` with a line that starts `git push ... main`; a trailing comment such as `git push origin claude/x # never push main`; `echo "(git push origin main)"`.
>
> My read is that #1 and #2 are worth fixing in this PR, and the rest can wait.

## Round 3 Reply (second local session, `c76b504` and `2dbc6c9`)

Posted to the PR, lightly condensed:

> **#1 and #2** are fixed in c76b504. Once an earlier segment runs `checkout`, `switch`, `rebase`, `worktree` (other than `list`/`prune`), `branch -m/-u/--track` or `symbolic-ref HEAD`, the current branch is unknown, and `HEAD`, `@`, `$(git branch --show-current)` and a bare push are blocked. Pushes to literal `claude/*` names stay allowed. `cd` to a literal directory is followed, and the hook reads that directory's branch and config.
>
> For config: `-c` with `push.*`, `remote.*.push`/`mirror`, `branch.*.merge`/`remote`/`pushRemote` or `include*`, plus `--config-env`, `--git-dir`, `--work-tree` and `GIT_CONFIG_*`/`GIT_DIR` in the environment, all block a push. `git config` writes to those keys and `git remote --mirror` are blocked outright. The hook reads `remote.<name>.push` on every push, not only bare ones, because git also applies it to a refspec that names only a source. A bare push also reads the push remote, `push.default` and the upstream. `matching` mode and the `:` refspec are blocked.
>
> **#3:** added `arch`, `xcrun`, `caffeinate`, `script` and `find -exec`, plus the shells `csh` and `tcsh`. A push run through `find` is blocked like one through `xargs`.
>
> **#4 and the over-blocking:** 2dbc6c9 replaces the separate heredoc, quote and `$'...'` regexes with one pass that tracks quotes, `$(...)` and backticks. All five evasions are now blocked. Multi-line `-m`/`--body` text, trailing comments and `echo "(git push origin main)"` are now allowed. `-c alias.P` matches case-insensitively, and `--config-env` is blocked.
>
> Each repro has a BLOCK test, with ALLOW controls next to it. The suite is now 175 tests.
>
> **Still open:**
> - `git checkout main; echo $(git push)` is allowed: the hook checks substitutions before the commands around them. Left as an evasion shape rather than a likely mistake.
> - Blocked, all failing closed: `git rebase origin/main && git push origin HEAD` (rebase is treated as a branch switch); `git checkout <file> && git push` without `--`; `git push origin "claude/$(date +%Y%m%d)-fix"`.
> - Remote and interpreter forms (`ssh host "git push ..."`, `su -c`, `python -c` with subprocess) are out of scope.

## Round 3 Verification: Not Completed

A verification of round 3 was started twice in the cloud session and stopped each time by its safety classifier, once while writing a probe harness and once during a read-only review of the guard. The work was reassigned to the local reviewer, then superseded by the decision to replace the guard (PRD EN1 to EN5). No round 3 verification results exist.
