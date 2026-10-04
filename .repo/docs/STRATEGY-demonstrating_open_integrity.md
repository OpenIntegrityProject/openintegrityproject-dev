# Strategy: Demonstrating Open Integrity
> - _github: [openintegrityproject-dev/.repo/docs/STRATEGY-demonstrating_open_integrity.md](https://github.com/OpenIntegrityProject/openintegrityproject-dev/blob/main/.repo/docs/STRATEGY-demonstrating_open_integrity.md)_
> - _Draft: 2026-10-03, prepared by Claude Code for review by Christopher Allen_

[![License](https://img.shields.io/badge/License-BSD_2--Clause--Patent-blue.svg)](https://spdx.org/licenses/BSD-2-Clause-Patent.html)
[![Project Status: WIP](https://www.repostatus.org/badges/latest/wip.svg)](https://www.repostatus.org/#wip)

This document states what this repository and `OpenIntegrityProject/oi-demo` must show for Open Integrity to be demonstrated, not just described. It sits above the [workflow PRD](PRD-human_agent_workflow.md), the requirements documents, and the [`oi-demo` plan](PLAN-oi_demo_bootstrap.md): those say how to build and run things, and this one says which claims they exist to prove.

It is measured against the goals in `OpenIntegrityProject/core`: the [problem statement](https://github.com/OpenIntegrityProject/core/blob/main/docs/Open_Integrity_Problem_Statement.md) and the [roadmap](https://github.com/OpenIntegrityProject/core/blob/4140bb97f41260d0ff8fb979e958103da37eb282/ROADMAP.md).

## The Claim to Demonstrate

`core` states the project's purpose: a Git repository can serve as a **cryptographic root of trust** with a continuing **chain of trust**, giving integrity, provenance, and accountability that anyone can check **independently of the hosting platform**, using Git's native SSH signing and no changes to Git.

A demonstration succeeds when a skeptical outsider, holding only a clone obtained from anywhere, Git, `ssh-keygen`, and a published verifier, can answer these questions about the repository without trusting GitHub, the maintainers, or the demonstration's own prose:

1. Where did this repository begin, and who began it?
2. Who was allowed to sign each commit, and was that authority granted by someone who held it?
3. Who wrote each change, and who approved it into `main`?
4. What happened when a key was added, retired, or misused?
5. Would tampering, at any point in the history, be detected?

Everything below serves those five questions.

## Demonstration Goals

Each goal names the risk from `core`'s problem statement that it answers. A goal is met only when it is shown by a real event in a public repository and checked by the verifier, not when it is documented or covered only by tests.

| Goal | Shows | Answers `core` risk | Status |
|---|---|---|---|
| **D1 Root of trust** | An empty, signed inception commit whose committer is its key's fingerprint, verifiable from any clone | Unsigned first commits allow repository forgery; no method verifies origin | Shown (this repository, `oi-demo`); not yet checked with `core`'s audit script |
| **D2 Delegated authority** | Signers added by commits signed by keys already authorized, judged by the parent's signers file so no key authorizes itself | No auditable way to delegate signing; inception key as single point of failure | Shown (R2, R3) |
| **D3 Roles** | Separate authority for commits, for `main` and the trust files, and for tags | Push access and commit access are intertangled | Shown for commits and `main`; tags defined (R5) but no tag exists |
| **D4 Authors and committers** | Agents and other contributors author on branches; a human approves by signing the merge; the authors' signed commits stay in `main`'s history | Committers can alter attribution; squash and rebase lose author signatures; deleted branches erase evidence | Shown in part: merge commits keep agent commits reachable; the merge record (PRD MR1 to MR5) is not built |
| **D5 Key lifecycle** | A key rotated, a key expired, and a key revoked, each as a recorded event with a visible effect on what verifies | Old keys stay trusted; revoked keys are not rejected | Not shown (K3, K5 not met) |
| **D6 Tamper detection** | Forged, unauthorized, self-authorizing, and rewritten commits each fail verification, publicly | Unsigned or unauthorized commits can be merged; history can be rewritten | Shown only in regression tests, not in a public repository |
| **D7 Platform independence** | The same verdicts from a clone hosted somewhere other than GitHub, with GitHub's "Verified" badge playing no part | Trust tied to one hosting provider | Not shown; enforcement and the process record are GitHub-specific today |
| **D8 Readable trust history** | A report of the repository's trust events, in the spirit of `core`'s "Summary of Trust Evolution" table | Trust exists only as raw signatures nobody reads | Not shown; the verifier prints per-commit lines only |

## Why Agents Are the Demonstration Case

`core` describes authors who hold no key permissions and committers who merge their work, and lists the risks between them. It does not mention AI agents. This repository's distinctive contribution is to use Claude Code agents as those authors:

- An agent signs its own commits with its own key, listed only in `allowed_commit_signers`, so it can author but never move `main` or change the trust files (D3, D4).
- A human approves the agent's work by signing the merge with a Secure Enclave key (D4).
- Two kinds of agent key, a local hardware key and a cloud key held by Anthropic, show that a signature proves only what the key's custody supports (findings F6, F9).

This makes the author-and-committer problem concrete and current: an agent's mistakes or a prompt injection are exactly the "author whose work must be checked before it is trusted" that `core` describes. The [workflow PRD](PRD-human_agent_workflow.md) governs how that collaboration runs day to day; this strategy treats it as the vehicle for D4, not the goal itself.

## Principles

- **P1 Validity lives in Git.** Whether a commit or tag is valid is decided only by the verifier against the repository's own signers files. Platform features (rulesets, required checks, GitHub's "Verified" badge) may enforce or display that result, but never define it. This is `core`'s platform-agnostic inspection, and the PRD's EN3.
- **P2 Enforcement may be platform-specific; evidence may not.** Rulesets, Actions, and agent identities on GitHub are acceptable ways to prevent mistakes. Anything a verifier or reader needs later (who approved, what was merged, which key signed) must be in the commits, not only in pull request pages or comments.
- **P3 Show failures, not only successes.** A trust system is demonstrated by what it rejects. Every goal that guards against a risk needs a public example of that risk being caught (D6).
- **P4 Progressive trust.** Authority grows by recorded steps from the inception key, as in `core`'s Inception Authority to Delegated Authority progression, and each step is a commit a reader can inspect.
- **P5 One specification.** Open Integrity's conventions (inception commit form, signers files, roles, revocation) have one normative home, and `core`'s audit script and this repository's verifier agree on them.

## How the Current Work Measures Against `core`

### Where It Goes Further Than `core`'s Roadmap

The roadmap orders work by version series, from Inception Authority (v0.1) through Delegated Authority (v0.4) to v1.0. This repository has demonstrated parts of later series before earlier ones were finished in `core`:

| `core` roadmap item | Series | Here |
|---|---|---|
| Verify all commits against authorized keys | v0.1 | `verify_commit_signatures.sh` (R1 to R7) |
| Manage `allowed_signers` files | v0.2 | Bootstrap writes them as signed commits |
| Merge strategies that keep trust chains; GitHub Actions verification | v0.3 | Merge commits only; `staging/main` and the `verify` check |
| Delegated Authority, chain-of-trust verification | v0.4 | R2, R3 |
| Trust roles for commits, tags, releases | Future opportunity | `allowed_main_signers`, `allowed_tag_signers` |
| Hardware-backed keys | v1.0 | Secure Enclave keys required for `main`, tags, trust files |

The roadmap's timeline (v1.0 in Q2 2026) has passed, and `core`'s documents were last updated in March 2025. The roadmap's ordering no longer describes the actual state of the project.

### Where It Diverges

- **Inception key after delegation.** `core`'s design says the inception key is no longer used after the first transition commit ("Superseding Keys"). Here the inception key stays in `allowed_commit_signers` (limitation L5), kept off `main` only by R4.
- **Inception and commit conventions.** The bootstrap adds an `OI-Bootstrap-Step` trailer, and later commits use a name rather than the key fingerprint as committer. Neither this repository's nor `oi-demo`'s inception commit has been checked with `core`'s `audit_inception_commit-POC.sh`.
- **Process record.** `core` prefers in-repository issues and platform-independent project management. The PRD makes GitHub pull requests and status comments the coordination record. That is acceptable for coordination under P2 only if the merge record (PRD MR1 to MR5) carries what matters into `main`.
- **Enforcement.** `core`'s enforcement guide relies on GitHub's own signed-commit rule. This repository deliberately does not (F7, F9): GitHub cannot check repository signers files, and its merge button signs with GitHub's key.

### What `core` Asks For That Is Not Yet Planned Anywhere

- **Revocation with a timestamp.** `core` proposes timestamped revocation recorded with `git notes`. Notes are not fetched by default, which conflicts with P1 unless the verifier fetches them. No mechanism is chosen (K5).
- **Contributor consent.** `core`'s "agreement chain of consent" has no counterpart here beyond `Signed-off-by`.
- **Repository identity.** `core`'s `did:repo` identifier, built from the inception commit, is not used by either demonstration repository.
- **Independent audit reports** of the kind `core` sketches (D8).
- **Progressive Trust terminology.** `core` standardizes it in script output; this repository's verifier does not use it.

## Sequence

Each stage ends with something an outsider can check. Stages are ordered by which goals they complete, not by `core`'s version series.

### Stage 1: Agree on One Specification

- Decide where Open Integrity's conventions are normative (P5). See the first decision below.
- Run `core`'s audit script against both demonstration repositories and record the differences.
- Decide the inception key's status after delegation.

Completes D1.

### Stage 2: Make `main` Carry Its Own Story

- Build the merge record (PRD MR1 to MR5), so each merge in `main` names the pull request, its commits, and the key that signed each.
- Land the PRD's agent identity and branch model, so agents author and the human integrates (D4).

Completes D4.

### Stage 3: Show What Is Rejected

- In `oi-demo`, preserve on named branches, never merged, a forged commit, a commit by an unlisted key, a commit by a key adding itself, and a rewritten history, each with the verifier's failure output recorded.
- Run the verifier on `oi-demo` from a clone hosted outside GitHub and record identical results.

Completes D6 and D7.

### Stage 4: Live a Key's Whole Life

- Rotate a device key before its Secure Enclave identity expires (K3), add a device with proof of possession (K4), and revoke a key by the chosen mechanism (K5).
- Sign and verify a release tag (R5).

Completes D3 and D5.

### Stage 5: Make the History Readable

- Add a trust-history report to the verifier, and a browser-based verifier (`oi-demo` plan, Phase 3), so a reader needs no shell to check the claims.

Completes D8.

## Decisions Needed

These change the shape of later work and should be settled before Stage 2:

- **Where the specification lives.** Options: `core` remains normative and this repository conforms; this repository's requirements become normative and `core` is updated to match; or a separate specification document both implement. Recommended: the verifier's requirements move into `core` as the specification, since `core` is the project's public home, with the scripts following once they converge.
- **Inception key after delegation.** Retire it from `allowed_commit_signers`, as `core` describes, or keep it for working branches, as now. Recommended: retire it in `oi-demo`, as the demonstration of `core`'s design.
- **Revocation mechanism.** `valid-before` dates in the signers files, a dated revocation list in the repository, or `git notes`. Recommended: in-repository files, which every clone carries (P1).
- **Where the process record lives.** GitHub pull requests with the merge record copied into `main`, or in-repository issues as `core` prefers. Recommended: the former for now, judged by P2.
- **Verifier language.** `core`'s scripts and this verifier are both zsh. A browser verifier (Stage 5) needs a second implementation; decide whether that becomes the reference.

## Out of Scope for the Demonstration

From `core`'s future opportunities, left for after D1 to D8 are shown: multi-source key authentication, decentralized storage and distribution (IPFS, BitTorrent, DHT), personal developer trust roots across repositories, threshold signatures, privacy-preserving trust manifests, and federation between repositories.

## Document Map

| Level | Document | Answers |
|---|---|---|
| Strategy | This document | What must be demonstrated, and why |
| Product | [PRD-human_agent_workflow.md](PRD-human_agent_workflow.md) | How humans and agents work together |
| Requirements | [REQUIREMENTS-verify_commit_signatures.md](REQUIREMENTS-verify_commit_signatures.md), [REQUIREMENTS-merge_and_bootstrap.md](REQUIREMENTS-merge_and_bootstrap.md), [REQUIREMENTS-agent_sessions.md](REQUIREMENTS-agent_sessions.md) | What the tools must do |
| Plan | [PLAN-oi_demo_bootstrap.md](PLAN-oi_demo_bootstrap.md) | What is being done next, by whom |
