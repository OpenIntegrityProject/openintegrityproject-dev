# Requirements for Zsh Script "Verify Commit Signatures"
> - _github: [openintegrityproject-dev/.repo/docs/REQUIREMENTS-verify_commit_signatures.md](https://github.com/OpenIntegrityProject/openintegrityproject-dev/blob/main/.repo/docs/REQUIREMENTS-verify_commit_signatures.md)_
> - _Updated: 2026-10-03 by Christopher Allen <ChristopherA@LifeWithAlacrity.com>_

[![License](https://img.shields.io/badge/License-BSD_2--Clause--Patent-blue.svg)](https://spdx.org/licenses/BSD-2-Clause-Patent.html)
[![Project Status: WIP](https://www.repostatus.org/badges/latest/wip.svg)](https://www.repostatus.org/#wip)

This document applies to `verify_commit_signatures.sh` **version 0.2.00 (2026-10-02)** and its associated files:

> **Origin:**
> - Script: [`.repo/scripts/verify_commit_signatures.sh`](../scripts/verify_commit_signatures.sh)
> - Regression test: [`.repo/scripts/tests/TEST-verify_commit_signatures.sh`](../scripts/tests/TEST-verify_commit_signatures.sh)
> - CI workflow: [`.github/workflows/verify-signatures.yml`](../../.github/workflows/verify-signatures.yml)

It records both the rules the script enforces and the findings from building it, because several design decisions follow from what the tools turned out *not* to support.

## General Requirements

The script must follow [REQUIREMENTS-Zsh_Core_Scripting_Best_Practices.md](https://github.com/OpenIntegrityProject/core/blob/main/src/requirements/REQUIREMENTS-Zsh_Core_Scripting_Best_Practices.md). It must depend only on zsh, Git, and OpenSSH, plus POSIX `awk`, `od`, `base64`, `grep`, and `tr`. It must never read private key material and must never modify the repository.

## Trust Model

### Signer Roles

Trust is expressed by files in `.repo/config/verification/`, each in OpenSSH `allowed_signers` format:

| File | Lists | Governs |
|---|---|---|
| `allowed_commit_signers` | Every approved key: human Secure Enclave keys, human software keys, agent keys | Every commit |
| `allowed_main_signers` | Human Secure Enclave keys only | Commits on the protected branch's first-parent chain, and any commit that changes `.repo/config/verification/` |
| `allowed_tag_signers` | Human Secure Enclave keys only | Signed tags |

Principals name one key on one device or agent (for example `@ChristopherA/chryseikori-se`, `@claude-code-web`), so a single key can be revoked by removing one line.

### Rules

- **R1 Inception.** *(Required)* The repository must have exactly one root commit. It must have Git's empty tree, its committer name must be an SSH key fingerprint (`SHA256:…`), and it must be signed by that key.
- **R2 Before the signers file.** *(Required)* Until a parent commit contains `allowed_commit_signers`, only the inception key may sign. This lets the inception key create the first signers file, as the inception commit message requires.
- **R3 Commit authorization.** *(Required)* Every other commit must carry a valid SSH signature in the `git` namespace by a key listed in `allowed_commit_signers` **as of its first parent**. Reading the parent's version means a key can never authorize itself, and every change to a trust file is judged by the version before it.
- **R4 Main signers.** *(Required)* Once a commit's first parent contains `allowed_main_signers`, that commit must also verify against it if either:
  - it is on the protected branch's first-parent chain, or
  - its diff against its first parent touches `.repo/config/verification/`. A merge that brings in trust-file changes therefore counts as changing them.
- **R5 Tags.** *(Required)* Every tag must be annotated and SSH-signed by a key in `allowed_tag_signers` **as of the tagged commit**. Lightweight tags fail.
- **R6 Time.** *(Required)* Signatures are checked as of the commit's committer date, or the tag's tagger date, so `valid-before` and `valid-after` judge when something was signed, not when it is verified.
- **R7 Full history.** *(Required)* Shallow clones must be refused, since R1 to R4 need every ancestor.

### Protected Branch

The protected branch is `origin/main` by default, else `main`, and can be set with `--protected <ref>` (or `--protected ''` for none). CI passes `--protected HEAD` on `main` and on `staging/*` branches, so a commit is checked under `main`'s rules on a staging branch *before* `main` is fast-forwarded to it.

## Output and Exit Status

- One line per commit: `<id> OK <principal>[ main:<principal>] <KEYTYPE> SHA256:<fingerprint>[ flags=0xNN UP=0|1 UV=0|1 counter=N]`, or `<id> FAIL <reason>`.
- One line per tag, in the same form, prefixed `tag <name>`.
- A summary line for commits and, when tags exist, for tags.
- `--quiet` prints only failures and summaries.
- Exit status: `0` all verified, `2` usage, `3` I/O or repository error (including shallow clones), `4` one or more failures.

## Security-Key Signature Flags

For `sk-*` signatures the script must decode the SSHSIG blob and report the authenticator flags byte and counter: user presence (`0x01`) as `UP`, user verification (`0x04`) as `UV`. It reports them for the record and must not enforce them: on macOS Secure Enclave keys the flags are identical whether or not the key requires Touch ID (F2), so they cannot distinguish a human signer from an agent. Roles come only from the signers files.

## Repository Enforcement (GitHub)

The verifier detects violations; GitHub rulesets prevent them. Two rulesets are required on `main`, because a ruleset's bypass list applies to every rule in it:

1. **`main: verified history`** with no bypass actors: block deletion, block non-fast-forward updates, and require the `verify` status check from GitHub Actions (`integration_id` 15368). The check is matched by the workflow **job name** `verify`: renaming the job, or moving it to another app, silently stops the ruleset from being satisfiable, and must be done together with a ruleset update.
2. **`main: only admins update`**: the `update` rule, with repository admins as the only bypass actors.

Together these mean `main` only moves to commits that already passed `verify` elsewhere, and only an admin can move it. The working flow is: agents push to `claude/*`; a human merges locally with a Secure Enclave key and pushes to `staging/main`; once `verify` passes, the human runs `git push origin HEAD:main`. A direct push of an unchecked commit is refused with `GH013 … Required status check "verify" is expected` (tested 2026-10-02).

Merging through GitHub's web UI is incompatible with this model: GitHub signs those commits with its own key, which is in no signers file. The merge procedure itself is specified in [REQUIREMENTS-merge_and_bootstrap.md](REQUIREMENTS-merge_and_bootstrap.md).

### CI Supply Chain

- **S1** *(Required)* Third-party actions must be pinned to a full commit SHA, with the tag in a comment (`actions/checkout@<sha> # v5.1.0`). A tag can be moved; a SHA cannot.
- **S2** *(Required)* The workflow must run with `permissions: contents: read` and must not use secrets.
- **S3** *(Recommended)* Changes to the runner image (`ubuntu-latest` moves to Ubuntu 26 from 2026-10-19) should be confirmed by a green run before they matter; pinning `runs-on` to a versioned image is an option if they do not.

## Findings

These were established on 2026-10-02 while building the script.

- **F1 No user-verification option in allowed signers.** OpenSSH's `allowed_signers` format accepts only `namespaces`, `valid-after`, `valid-before`, and `cert-authority`. `verify-required` and `no-touch-required` exist only for `authorized_keys` and are rejected as "unknown key option" (tested on OpenSSH 9.6p1 and 10.3p1). `git verify-commit` therefore cannot require biometric signing.
- **F2 macOS Secure Enclave keys do not assert user verification.** Keys created with `sc_auth create-ctk-identity -k p-256-ne -t bio` and used through `/usr/lib/ssh-keychain.dylib` (macOS 27.0.1, OpenSSH 10.3p1) are `sk-ecdsa-sha2-nistp256@openssh.com`. Touch ID prompts on every signature, but the flags byte is `0x21`: user presence set, **user verification not set**. Bit `0x20` is reserved in WebAuthn; its meaning here is unknown. A key created with `-t none`, which signs with **no prompt at all**, produces the same `0x21` with `UP=1` (local agent commits in `oi-demo`, `c76b504` to `641a941`), so not even user presence is meaningful for these keys.
- **F3 The counter does not advance.** All five signatures observed from the same Secure Enclave key over several hours (one test signature and commits `2bba62e`, `2a67716`, `83e71de`, `dfe5c64`) carried counter `1`, so the counter cannot detect a cloned key. The `-ne` (non-exportable) key type makes cloning unlikely in the first place.
- **F4 Biometric signing is a declaration, not a proof.** Because of F1 and F2, "signed with Touch ID" cannot be checked from a signature, and a Touch ID key cannot be told apart from a no-prompt key by its signatures. It rests on how the key was created, which the approving commit should record (for example, the `sc_auth` command and `bio` protection).
- **F5 Secure Enclave identities expire.** `sc_auth list-ctk-identities` reports one-year validity (keys created 2026-05-07 are valid to 2027-05-07). Whether SSH signing stops at expiry is untested; plan rotation before then, or use `valid-before` to make the expiry explicit.
- **F6 Claude Code on the web signs with an Anthropic-held key.** Cloud sessions sign commits as `Claude <noreply@anthropic.com>` with `ssh-ed25519 …KCtVErAQfpmprtUJCZ2w7` (`SHA256:32dP45eSMmVSt/G/CGvcxl/P+MO3Nwj9xeTh/GSA2wc`). The private key is outside the session container. Two separate sessions (the one that built these scripts in `openintegrityproject-dev`, and the one that opened `oi-demo` PR #1) signed with the same key, so it is **not per session**. Whether it is per account, per organization, or global, and whether it rotates, is unconfirmed; an inquiry to Anthropic support is drafted but not confirmed sent. If the key is global, a valid signature proves only that *some* Claude session made the commit.
- **F7 GitHub's limits.** A required status check refuses a direct push of any commit that has not already passed the check on another ref, which is why the staging flow is needed. GitHub cannot check signatures against repository signers files itself, and rulesets on private repositories require a paid plan.
- **F8 Secure Enclave keys need an exported key handle for SSH.** `sc_auth create-ctk-identity` creates the identity but no SSH key file, so the key never appears in `ssh-add -L`. The handle ("stub") is exported with `ssh-keygen -K -w /usr/lib/ssh-keychain.dylib -N ""`, which writes `id_ecdsa_sk_rk_<label>` and `.pub` for every identity (press Return at its PIN prompt), and loaded with `ssh-add -S /usr/lib/ssh-keychain.dylib <stub>`. The agent forgets it at logout or reboot, so `ssh-add -S` must be repeated; Git signs through the agent, using the `.pub` path in `user.signingkey`.
- **F9 GitHub's "Verified" badge is a different check.** GitHub marks a commit Verified only when the signing key is registered to the GitHub account that owns the committer email. Agent keys are deliberately not registered to anyone's account, so valid `@claude-local/*` commits show as Unverified on GitHub. Validity in an Open Integrity repository is decided only by this verifier against the repository's signers files.
- **F10 An unanswered Touch ID prompt yields an empty signature, not an error.** When nobody answers the Secure Enclave's Touch ID prompt, `git commit -S` still exits 0 and writes a commit whose SSH signature block carries the key and flags but a zero-length signature value. `git verify-commit` reports "error in libcrypto", and this verifier reports `FAIL signature does not verify`. Observed twice in a row on 2026-10-03 with `sc_auth` keys through `/usr/lib/ssh-keychain.dylib`; re-signing with someone at the Mac (`git commit --amend --no-edit -S`) produced a valid signature. A signing step therefore cannot be trusted from its exit status: verify the commit after signing it.

## Known Limitations

- **L1 Backdating.** Committer and tagger dates are chosen by the signer, so a holder of a key past its `valid-before` can backdate. Git has the same weakness. A fix needs a trusted time, such as the push time recorded by the forge or a signed timestamp.
- **L2 Role bootstrap.** Until `allowed_main_signers` exists, any commit signer can create it. It must be created by a human Secure Enclave key (in this repository, commit `dfe5c64`).
- **L3 Trust in the CI runner.** Enforcement relies on GitHub Actions running the script faithfully and on the ruleset configuration. Anyone can re-run the script locally to check independently.
- **L4 Tag payload extraction** uses the first armored SSH signature block in the tag object. A tag message containing such a block before the real signature would fail verification rather than pass.
- **L5 Software keys remain in `allowed_commit_signers`.** The inception key and agent keys can still sign working branches; R4 keeps them off `main` and away from the trust files.

## Open Questions

- Scope and rotation of the Anthropic cloud signing key (F6).
- Whether a future macOS release will set the user-verification flag (F2), at which point the script can enforce `UV=1` for main and tag signers.
- A key-addition ceremony for new devices: approve a key with an existing Secure Enclave key, then require one commit from the new key as proof of possession.
- Revocation: removing a key stops future commits, but past commits it signed still verify. Should the verifier support an explicit revocation list with a date?
- Portability beyond zsh, as part of the audit-script rewrite (for example, `stat -f` in `core`'s audit script is BSD-only).
- Compatibility with `core`'s `audit_inception_commit-POC.sh`: neither this repository's nor `oi-demo`'s inception commit has been run through it. The bootstrap also adds an `OI-Bootstrap-Step` trailer to later commits, and later commits use a name rather than the key fingerprint as committer; whether Open Integrity conventions require either is unrecorded.
- Tags: no tag has yet been created or verified in either repository, and no release process is defined.

## Regression Tests

`TEST-verify_commit_signatures.sh` builds throwaway repositories with throwaway keys. It must cover, at minimum:

- a valid chain (inception, signers file, approved signer);
- unsigned commits, unlisted signers, and a key approving itself;
- a non-inception key signing before the signers file exists;
- a non-empty inception commit, and an inception key that does not match the committer fingerprint;
- `valid-before` judged at the commit date in both directions;
- a second root commit, and a shallow clone;
- an agent commit merged to `main` by a main signer (passes), an agent commit directly on `main` (fails), and the same commit with no protected branch (passes);
- an agent changing trust files off `main` (fails), and a main signer changing them (passes);
- `--protected HEAD` on a staging branch;
- a tag by a tag signer (passes), by a non-tag signer (fails), a lightweight tag (fails), and a tag on a commit with no tag signers file (fails).
