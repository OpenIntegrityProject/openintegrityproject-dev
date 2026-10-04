# Strategy: Demonstrating Open Integrity in the Age of Agentic AI
> - _github: [openintegrityproject-dev/.repo/docs/STRATEGY-demonstrating_open_integrity.md](https://github.com/OpenIntegrityProject/openintegrityproject-dev/blob/main/.repo/docs/STRATEGY-demonstrating_open_integrity.md)_
> - _Draft: 2026-10-03, prepared by Claude Code for review by Christopher Allen_

[![License](https://img.shields.io/badge/License-BSD_2--Clause--Patent-blue.svg)](https://spdx.org/licenses/BSD-2-Clause-Patent.html)
[![Project Status: WIP](https://www.repostatus.org/badges/latest/wip.svg)](https://www.repostatus.org/#wip)

This document states what Open Integrity must demonstrate, and for whom, now that AI agents write, review, and attack code. It sits above the [workflow PRD](PRD-human_agent_workflow.md), the requirements documents, and the [`oi-demo` plan](PLAN-oi_demo_bootstrap.md): those say how to build and run things, and this one says which claims they exist to prove.

It is measured against the goals in `OpenIntegrityProject/core`, chiefly its [problem statement](https://github.com/OpenIntegrityProject/core/blob/main/docs/Open_Integrity_Problem_Statement.md) and [roadmap](https://github.com/OpenIntegrityProject/core/blob/4140bb97f41260d0ff8fb979e958103da37eb282/ROADMAP.md), and the public summary at <https://developer.blockchaincommons.com/open-integrity/>.

## What Experience Has Shown

**Open Integrity works for teams that live in local Git and sign everything.** A signed inception commit, signers files, and a verifier give a history that anyone can check from any clone.

**It fights the web.** GitHub's web editor, merge button, and suggested changes create commits signed by GitHub's own key, which a repository's signers files cannot authorize. A project that wants every commit verified must forbid those features and land changes through a local, signed merge. This repository does exactly that (`merge_pr.sh`, a `staging/main` branch, rulesets, Secure Enclave keys), and the result is safe but heavy: merging a one-file fix takes a scripted local merge, a Touch ID prompt, and a wait for CI, because `gh pr merge` and the merge button are forbidden.

**So most projects stop at the first step.** Signing an inception commit costs one command and is worth doing for every repository. Signing every later commit, and refusing web edits, is a cost small projects and less experienced developers will not pay.

## What Agentic AI Changes

- **The ceremony gets cheaper.** An agent can create keys, write signers files, sign, verify, and explain failures. What made Open Integrity hard to adopt was mostly procedure, and procedure is what agents are good at.
- **Signatures get cheaper too, and so mean less.** An agent can sign a thousand plausible commits a day. A valid signature shows which key made a commit; it says nothing about whether anyone competent looked at it. The scarce thing is no longer authorship but **accountable review**.
- **Review is increasingly done by AI.** Few open projects can fund human security audits. AI review is cheap and uneven, and it is rarely disclosed: a reader cannot tell whether a release was reviewed by a person, a model, both, or nobody.
- **Attack is done by AI as well.** Vulnerabilities are found and exploited faster and at greater scale, and maintainers also face floods of AI-generated, unverified vulnerability reports. Disclosure has to work in both directions under that load.

The question Open Integrity should now answer is broader than "who made this commit?" It is: **what claims are being made about this repository's content and review, who or what made them, and can anyone verify them independently?**

## The Claim to Demonstrate

A demonstration succeeds when an outsider, holding only a clone obtained from anywhere, Git, `ssh-keygen`, and a published verifier, can answer these questions without trusting GitHub, the maintainers, or the demonstration's own prose:

1. Where did this repository begin, and who began it?
2. Which versions did the maintainers stand behind, and with which keys?
3. For each such version, who or what reviewed it, how, and what was not reviewed?
4. Who was allowed to sign, and was that authority granted by someone who held it?
5. What happened when a key was added, retired, or misused, and would tampering be detected?

A project at a lower tier (below) answers fewer of these, and says so.

## Adoption Tiers

Open Integrity should be adopted in steps, each useful on its own and each honest about what it does not prove. This is `core`'s progressive trust applied to adoption, not only to keys.

| Tier | What is signed | What it proves | Web edits allowed |
|---|---|---|---|
| **0 Anchor** | The inception commit | Where the repository began and which key began it | Yes |
| **1 Checkpoints** | Version tags, by keys in the repository's tag signers file | Which versions the maintainers stand behind | Yes, between tags |
| **2 Disclosure** | A review statement bound to each version tag | Who or what reviewed that version, how, and with what known gaps | Yes, between tags |
| **3 Full chain** | Every commit, with roles for `main`, tags, and trust files | Who authored and who approved every change | No: changes land by local signed merge |

Tiers 1 and 2 are the new center of the strategy. They accept that the commits between releases may be made on the web, by agents, or by people with no keys, and they move the cryptographic claim to the point where it matters to users: the version they install.

A technical limit belongs in plain view. GitHub signs web commits with GPG, and this verifier checks SSH signatures only, so at Tiers 1 and 2 the commits between tags are not verified at all. The claim is about the tagged tree, not the path to it.

Tier 3 is what this repository and `oi-demo` already demonstrate. It remains the right choice for repositories whose history is itself the product: trust registries, specifications, and the Open Integrity tools.

## Review Disclosure

Tier 2 asks each version to carry a signed **review statement**. It should say, at minimum:

- **Who or what reviewed.** A person, an AI system (product, model, and version), or both, and who directed the review.
- **What was reviewed.** The commit range or tree, the scope (all code, changed code only, dependencies, build), and what was excluded.
- **How.** Manual reading, tests, fuzzing, static analysis, AI review with its instructions, and so on.
- **What was found** and what was done about it, including findings deferred.
- **What it does not claim.** "No human security audit" is a legitimate, useful statement when true.
- **Where to report problems,** and the project's disclosure policy, consistent with its `SECURITY.md`.

Each statement is signed by whoever stands behind it. An AI reviewer that holds its own key signs its own statement as itself, under an agent role, and a maintainer signs the tag that adopts it. That keeps the human accountable for the release without pretending a human did the review.

The format should borrow from existing work rather than invent: software attestation formats (in-toto, SLSA provenance), vulnerability disclosure norms and `SECURITY.md`, and machine-readable vulnerability status (VEX). Open Integrity's contribution is to anchor such statements to the repository's own keys and inception commit, so they are checkable without the platform that hosts them.

Version numbers then mean something definite: a signed tag is a dated claim by named keys about a named tree and its review, not just a label.

## Demonstration Goals

Each goal is met only when shown by a real event in a public repository and checked by a published verifier, not when documented or covered only by tests.

| Goal | Tier | Shows | Status |
|---|---|---|---|
| **D1 Root of trust** | 0 | An empty, signed inception commit whose committer is its key's fingerprint | Shown here and in `oi-demo`; not yet checked with `core`'s audit script |
| **D2 Verified checkpoints** | 1 | A release tag verified against the repository's tag signers file, in a repository that also accepts web commits | Not shown; no tag exists in either repository, and the verifier has no tags-only mode |
| **D3 Review disclosure** | 2 | A release whose signed review statement names an AI reviewer and its limits, verified from a clone | Not shown; no format exists |
| **D4 Responsible disclosure loop** | 2 | A reported issue, its fix, and a later release whose review statement records both | Not shown |
| **D5 Delegated authority** | 3 | Signers added only by keys already authorized, judged by the parent's signers file | Shown (verifier rules R2, R3) |
| **D6 Authors and approvers** | 3 | Agents author on branches; a human approves by signing the merge; the agents' signed commits stay in history | Shown in part; the merge record (PRD MR1 to MR5) is not built |
| **D7 Key lifecycle** | 1 to 3 | A key rotated, expired, and revoked, each with a visible effect on what verifies | Not shown |
| **D8 Tamper detection** | 0 to 3 | Forged, unauthorized, self-authorizing, and rewritten history each fail verification, publicly | Shown only in regression tests |
| **D9 Platform independence** | 0 to 3 | The same verdicts from a clone hosted outside GitHub | Not shown |
| **D10 Lightweight adoption** | 0 to 2 | A small project, worked largely through GitHub's web interface and an agent, reaching Tier 2 without a local signing workflow beyond tags | Not shown |

## Principles

- **P1 Validity lives in Git.** Whether a commit, tag, or review statement is valid is decided by a verifier against the repository's own files. Platform features may enforce or display that result but never define it.
- **P2 Weight follows need.** Each tier is a complete, honest position. Do not ask a small project for Tier 3, and do not let a Tier 1 project imply Tier 3 guarantees.
- **P3 Disclose who or what.** Every claim names whether a person, an AI system, or both stood behind it. Undisclosed AI review is the problem; disclosed AI review is a useful, checkable fact.
- **P4 Say what is not claimed.** A statement's limits are part of the statement.
- **P5 Show failures, not only successes.** A trust system is demonstrated by what it rejects.
- **P6 One specification.** Open Integrity's conventions have one normative home, and `core`'s scripts and this repository's verifier agree on them.

## How the Current Work Measures Against `core`

**Where it goes further.** This repository already demonstrates parts of `core`'s roadmap out of order: verification of every commit against authorized keys (v0.1), signers files managed by signed commits (v0.2), merge-commit workflows with CI verification (v0.3), delegated authority (v0.4), and separate signer roles and hardware-backed keys, which `core` lists as future opportunities. The roadmap's timeline, ending at v1.0 in Q2 2026, has passed.

**Where it diverges.** `core` retires the inception key after delegation; here it stays in `allowed_commit_signers`. The bootstrap's commit conventions (an `OI-Bootstrap-Step` trailer, named committers after inception) have not been checked with `core`'s audit script. `core` prefers in-repository issue tracking; the PRD makes GitHub pull requests the coordination record. `core`'s enforcement guide relies on GitHub's own signed-commit rule, which this repository cannot use (GitHub does not read repository signers files).

**What `core` does not yet address.** `core` assumes every contributor signs locally and that authority over commits is the main question. It has no tier below full signing, no account of web-based workflows, nothing on AI authors or reviewers, and nothing on review or vulnerability disclosure. These are the additions this strategy proposes.

**What `core` asks for that is not yet planned.** Timestamped revocation (proposed with `git notes`, which clones do not fetch by default), a cryptographic chain of contributor consent, `did:repo` repository identifiers, and independent audit reports.

## Sequence

Each stage ends with something an outsider can check.

### Stage 1: Agree on the Model

- Discuss the tiers and review disclosure publicly, starting with the meeting brief in [SLIDES-security_in_the_age_of_agentic_ai.md](SLIDES-security_in_the_age_of_agentic_ai.md).
- Decide where the specification lives (P6), and run `core`'s audit script against both demonstration repositories.

Completes D1.

### Stage 2: Checkpoints

- Add a tags-only mode to the verifier: check the inception commit and every version tag, and report the commits between them as unverified rather than failing.
- Sign and verify the first release tag in this repository and in `oi-demo`.

Completes D2.

### Stage 3: Disclosure

- Draft the review statement format, reusing existing attestation formats where they fit.
- Release a version of a real, small project with an AI review statement, a `SECURITY.md`, and nothing else beyond Tier 0.

Completes D3 and D10; D4 follows the first real report.

### Stage 4: Full Chain and Failures

- Build the merge record (PRD MR1 to MR5) and the PRD's agent identity and branch model.
- Publish rejected examples in `oi-demo`: forged, unauthorized, self-authorizing, and rewritten history, with the verifier's output.
- Verify from a clone hosted outside GitHub.

Completes D6, D8, and D9.

### Stage 5: Keys Over Time

- Rotate a device key before its Secure Enclave identity expires, add a device with proof of possession, and revoke a key by the chosen mechanism.

Completes D7.

## Decisions Needed

- **Review statement home.** In the signed tag's message, in a signed file the tag points to, or in `git notes` on the tagged commit. Recommended: a file in the repository, referenced from the tag, so every clone carries it (P1).
- **Agent keys for review.** Whether an AI reviewer signs its own statements with an agent key, or the maintainer signs on its behalf with the statement naming it. Recommended: the agent signs as itself where it can hold a key, as agents already do for commits here.
- **Where the specification lives.** Recommended: the verifier's requirements move into `core` as the specification, extended with the tiers and the review statement.
- **Inception key after delegation.** Recommended: retire it in `oi-demo`, as `core` describes.
- **Revocation mechanism.** Recommended: in-repository files that every clone carries, rather than `git notes`.
- **Which project goes first at Tier 2.** It should be small, real, and edited on the web.

## Out of Scope for Now

From `core`'s future opportunities: multi-source key authentication, decentralized storage and distribution, personal developer trust roots across repositories, threshold signatures, privacy-preserving trust manifests, and federation between repositories.

## Document Map

| Level | Document | Answers |
|---|---|---|
| Strategy | This document | What must be demonstrated, and why |
| Discussion | [SLIDES-security_in_the_age_of_agentic_ai.md](SLIDES-security_in_the_age_of_agentic_ai.md) | What to ask the community |
| Product | [PRD-human_agent_workflow.md](PRD-human_agent_workflow.md) | How humans and agents work together at Tier 3 |
| Requirements | [REQUIREMENTS-verify_commit_signatures.md](REQUIREMENTS-verify_commit_signatures.md), [REQUIREMENTS-merge_and_bootstrap.md](REQUIREMENTS-merge_and_bootstrap.md), [REQUIREMENTS-agent_sessions.md](REQUIREMENTS-agent_sessions.md) | What the tools must do |
| Plan | [PLAN-oi_demo_bootstrap.md](PLAN-oi_demo_bootstrap.md) | What is being done next, by whom |
