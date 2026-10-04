---
title: Security in the Age of Agentic AI
robots: noindex, nofollow
description: View the presentation with "Slide Mode"
type: slide
tags: Slides, Open Integrity
slideOptions:
  theme: simple
  transition: fade
  controls: true
  progress: true
  slideNumber: true
  center: true
---

<style>
.reveal { font-size: 24px; }
.reveal h1, .reveal h2 { line-height: 1.1em; }
.reveal ul { font-size: 1.1em; line-height: 1.3em; }
.reveal table { font-size: 0.8em; }
.reveal pre code { font-size: 0.65em; }
</style>

# Security in the Age of Agentic AI
## Disclosure, Signing, and Open Integrity
### Christopher Allen | Blockchain Commons | 2026-10-07

Note:
Discussion opener for the second half of the meeting. The goal is an open conversation, not a pitch. The slides set out one possible direction so there is something concrete to disagree with.

---

## The Question

* How do we disclose **who (or what)** reviewed a project's security?
* How should we do **code signing, versions, and tags** when human security audits are unaffordable?
* What **standards** would we like to see emerge for the content and security of repositories?

Note:
These are the questions from the meeting invitation. Most open projects never had a funded human audit; agentic AI makes the gap both more visible and more urgent.

---

## What Changed

* AI agents **write** code: more code, faster, uneven quality
* AI agents **review** code: cheap, uneven, rarely disclosed
* AI agents **attack** code: vulnerabilities found and exploited faster and at scale
* Maintainers receive **floods of AI-generated vulnerability reports**, many invalid

Note:
All four arrive at once, and all four land on the same small maintainer teams.

----

### ANNOTATION: Both Directions of Disclosure

**Inbound:** maintainers report a rising volume of AI-generated, unverified vulnerability reports. curl's lead maintainer has written publicly about this since 2024, and some programs now ask reporters to disclose AI use.

**Outbound:** regulation is starting to expect vulnerability handling from software producers; the EU Cyber Resilience Act's reporting obligations begin in 2026.

**Implication:** disclosure needs to say who or what did the work in both directions, reports and reviews alike.

---

## Open Integrity, Briefly

* A Git repository as a **cryptographic root of trust**
* A signed, empty **inception commit** anchors where it began
* **Signers files** in the repository say who may sign what
* Anyone can **verify from any clone**, without trusting the host

Note:
Blockchain Commons' earlier work. The page is developer.blockchaincommons.com/open-integrity, and the code is in the OpenIntegrityProject organization on GitHub.

----

### ANNOTATION: Open Integrity's Stated Goals

* Immutable proof of origin
* Signed commits and tags
* Tamper detection
* Trust delegation from the inception key
* Platform-agnostic validation: GitHub, GitLab, self-hosted

---

## What We Learned

* **Works well** for teams that live in local Git and sign everything
* **Fights the web:** GitHub's editor and merge button sign with GitHub's key, which a repository cannot authorize
* **Heavy for small projects** and less experienced developers
* In practice: **sign the inception commit**, then stop

Note:
I initialize nearly all my projects with an Open Integrity inception commit. Very few go further, because full signing means giving up web editing and the merge button.

---

## Signatures Got Cheap

* An agent can sign a thousand plausible commits a day
* A valid signature says **which key** made a commit
* It says nothing about **whether anyone competent looked**
* The scarce thing is no longer authorship: it is **accountable review**

Note:
This is the turn in the argument. Agentic AI makes signing easy, since an agent can run the whole key ceremony, and in the same stroke makes a signature worth less on its own.

---

## A Proposal: Adoption Tiers

| Tier | Signed | Proves | Web edits |
|---|---|---|---|
| **0 Anchor** | Inception commit | Where it began | Yes |
| **1 Checkpoints** | Version tags | Which versions maintainers stand behind | Yes |
| **2 Disclosure** | Review statement per version | Who or what reviewed, how, and the gaps | Yes |
| **3 Full chain** | Every commit, with roles | Who wrote and approved every change | No |

Note:
Progressive trust, applied to adoption. Each tier is honest about what it does not prove. Tiers 1 and 2 move the cryptographic claim to where users care: the version they install.

----

### ANNOTATION: The Limit at Tiers 1 and 2

* Commits between tags may come from the web, agents, or people without keys
* GitHub signs web commits with GPG; Open Integrity verifies SSH signatures
* So the claim is about the **tagged tree**, not the path to it
* Tier 3 remains right where the history is the product: registries, specifications, the tools themselves

---

## Review Disclosure

A signed statement bound to each release:

* **Who or what** reviewed: person, AI system and model, or both
* **What** was reviewed, and what was **excluded**
* **How:** reading, tests, fuzzing, static analysis, AI review
* **Findings** and what was done about them
* **What is not claimed:** "no human security audit" is a fine answer
* **Where to report** problems

Note:
The point is not to require human review. It is to stop leaving readers to guess. Undisclosed AI review is the problem; disclosed AI review is a checkable fact.

----

### ANNOTATION: A Sketch of a Review Statement

```yaml
release: v1.4.0
tree: 9f2c41e
reviewers:
  - kind: ai
    system: <product> <model> <version>
    directed_by: "@maintainer"
    scope: changed code since v1.3.0; dependencies excluded
    method: AI review with written instructions; test suite run
  - kind: human
    who: "@maintainer"
    scope: findings triage only
findings: 3 fixed, 1 deferred (issue #42)
not_claimed: no independent human security audit
report_to: SECURITY.md
signed_by: maintainer key, as listed in the repository's tag signers
```

A sketch only: the format should reuse in-toto, SLSA, VEX, and `SECURITY.md` conventions where they fit.

---

## Versions and Tags as Claims

* A signed tag becomes a **dated claim by named keys** about a named tree and its review
* Version numbers then mean something you can check
* An AI reviewer can sign **its own** statement under an agent key
* The maintainer signs the tag that **adopts** it, and stays accountable

Note:
This keeps the human responsible for the release without pretending a human did the review.

---

## What We Have Built So Far

* A verifier for every commit and tag against the repository's signers files
* Roles: agents may author; only hardware-backed human keys may change `main`, tags, or trust files
* Claude Code agents, local and cloud, sign their own commits as themselves
* A human approves each merge with Touch ID

**That is Tier 3, and it is heavy.** Tiers 1 and 2 are next.

Note:
github.com/OpenIntegrityProject/openintegrityproject-dev. Useful as proof that agents and humans can share a fully verified history; not a model most projects should copy.

---

## Questions for the Group

* What should a review statement **have to** say? What is optional?
* How should AI reviewers be **identified**: product, model, version, instructions?
* Should **AI-generated vulnerability reports** be labeled, and by whom?
* What does a version tag **promise** when no human audited the code?
* Which existing standards should this **build on** rather than reinvent?
* Who would **try Tier 2** on a real project?

Note:
Open the floor here. Capture answers; they feed the next draft of the strategy.

---

## Links

* Open Integrity: https://developer.blockchaincommons.com/open-integrity/
* Core repository: https://github.com/OpenIntegrityProject/core
* Strategy draft: https://github.com/OpenIntegrityProject/openintegrityproject-dev/blob/main/.repo/docs/STRATEGY-demonstrating_open_integrity.md

---

# Thank You
## Discussion
