# CI Claude Code Review — Requirements Table

**Spec:** `.specs/features/ci-claude-code-review/spec.md`
**Design:** `.specs/features/ci-claude-code-review/design.md`
**Tasks:** `.specs/features/ci-claude-code-review/tasks.md`
**Status:** Approved (derived from the approved spec, amended after the verifier pass)
**Created:** 2026-11-11

> Read each row alone: Scenario names the situation, Expression states the rule as conditions and outcomes, Complement says why the rule exists, Path tags success (SP) or error (EP).

---

## 1. When a review runs

A pull request event in a repository that adopted the review decides whether a review job starts at all.

| Requiriment | Scenario                                  | Expression                                                                                                                                                                                                                                                        | Complement                                                                                                                                                | Path |
| ----------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- |
| FR-001      | Ready PR is opened or updated             | **Given** a repository that adopted the review **When** a PR that is not a draft is opened, receives new commits, is reopened or is marked ready for review **Then** exactly one review is posted on that PR **And** its author is the GitHub Actions bot account | The goal: every reviewable PR gets one consolidated review with no manual step                                                                            | SP   |
| FR-002      | Adopting repository wiring                | **Given** a repository that wants the review **When** it adopts it **Then** it adds one small workflow file whose only job calls the shared workflow at the stable release tag **And** passes the token-list secret by name, never by blanket inheritance         | Review logic lives in one place; adopting must be a copy-paste, and personal accounts have no organisation-wide secret inheritance to rely on             | SP   |
| FR-003      | Adopting job grants its token permissions | **Given** the adopting workflow's job **Then** it grants read access to contents and write access to PR reviews **And** grants nothing else                                                                                                                       | A called workflow can only lower the permissions it receives, and new personal repositories start read-only; without this the shared job could never post | EP   |
| FR-004      | Draft PR                                  | **Given** a PR that is still a draft **When** any PR event fires **Then** the review job is skipped **And** a draft that later becomes ready is reviewed at that moment                                                                                           | Drafts change often; reviewing every draft push burns the limited Claude subscription quota                                                               | SP   |
| FR-005      | PR from a fork                            | **Given** a PR whose source branch lives in a different repository than the target **When** a PR event fires **Then** the review job is skipped, not run                                                                                                          | GitHub withholds secrets from fork PRs, so the review could never authenticate                                                                            | EP   |
| FR-006      | PR opened by Dependabot                   | **Given** a PR authored by the Dependabot bot **When** a PR event fires **Then** the review job is skipped **And** PRs from any other author are not affected by this rule                                                                                        | Dependabot runs receive Dependabot secrets, not Actions secrets, so the token list would be empty                                                         | EP   |
| FR-007      | New push while a review runs              | **Given** a review in progress for a PR **When** a newer run starts for the same repository and PR **Then** the older run is cancelled **And** runs for other PRs are untouched                                                                                   | The older review would judge stale code; the review is posted in a single call, so cancelling never leaves half a review                                  | SP   |

---

## 2. The shared repository

| Requiriment | Scenario                                                    | Expression                                                                                                                                                                                                                 | Complement                                                                                                                                                               | Path |
| ----------- | ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---- |
| FR-008      | Shared repository is public                                 | **Then** the shared repository is publicly readable **And** both public and private repositories of the owner can adopt the review                                                                                         | A private shared repository under a personal account can be called only by the owner's private repositories; public also removes a second secret per adopting repository | SP   |
| FR-009      | Reading the shared repository                               | **When** the job fetches the review skill **Then** it reads the shared repository at the same release tag the adopting repository calls, with the job's own token **And** leaves no stored credential behind on the runner | PR code runs on the same runner with unrestricted shell access; a persisted credential is one more thing it could read                                                   | SP   |
| FR-010      | Shared repository holds no secrets and never reviews itself | **Then** the shared repository holds no secret at all **And** none of its own workflows fire on its own pull requests                                                                                                      | Being public is safe only because nothing secret lives there; the adopting-file template is stored outside the workflow folder so it never runs there                    | SP   |

---

## 3. Choosing a Claude token

One secret holds several subscription tokens separated by semicolons; each run picks one.

| Requiriment | Scenario                           | Expression                                                                                                                                                                                                                         | Complement                                                                                            | Path |
| ----------- | ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ---- |
| FR-011      | Well-formed token list             | **Given** a token list with one or more entries **When** a run picks a token **Then** the result is exactly one entry with surrounding spaces removed **And** blank entries (from doubled or trailing separators) are never picked | Hand-edited secrets often carry stray spaces or a trailing separator; those must not break a run      | SP   |
| FR-012      | Spread across accounts             | **Given** a list of N non-blank tokens **When** many runs pick **Then** every one of the N tokens is chosen at least sometimes **And** no history of past picks is stored                                                          | Spreads usage across accounts' quotas without any state to maintain                                   | SP   |
| FR-013      | Token never appears in logs        | **When** a token is picked **Then** its value is masked before it is used anywhere **And** the log shows only its position in the list and the list size                                                                           | Shows which account ran (useful when one is rate-limited) without exposing the secret                 | SP   |
| FR-014      | Empty token list                   | **Given** a token list that is empty or contains only separators and spaces **When** a run picks a token **Then** the run fails before Claude starts **And** the error message says the token list is empty                        | A misconfigured secret should fail with a clear cause instead of an opaque authentication error later | EP   |
| FR-015      | Token reaches only the Claude step | **When** the picked token is handed on **Then** only the Claude step receives it **And** it is never placed in the job-wide environment                                                                                            | Limits the number of steps that can read the token                                                    | SP   |

---

## 4. Delivering and invoking the review skill

| Requiriment | Scenario                                | Expression                                                                                                                                                                                                                                                                                         | Complement                                                                                                                                                                                            | Path |
| ----------- | --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- |
| FR-016      | Skill installed where Claude can see it | **When** the job prepares the review **Then** the skill is installed in the runner user's personal skill folder, outside the checked-out project **And** the temporary copy of the shared repository is gone before Claude starts                                                                  | The Claude action replaces the project's own Claude folder with the target branch's version on every PR, deleting anything it did not have; a copy placed there would vanish                          | SP   |
| FR-017      | What Claude is asked to do              | **When** Claude starts **Then** it is asked to run the review skill on this PR number in this repository and to write the review in Portuguese **And** it is capped at a fixed turn limit **And** it may use only skill, read, write, edit, search, web and shell tools                            | Fixed language for the owner's team; the turn cap bounds a single run's quota use; write and edit let the skill save its findings file, and add no exposure because the shell is already unrestricted | SP   |
| FR-018      | Job permissions                         | **Then** the shared review job can read repository contents and write PR reviews **And** has no other permission, including no identity-token permission                                                                                                                                           | Least privilege; the identity-token permission is only needed for the Claude GitHub App, which this design does not use                                                                               | SP   |
| FR-019      | Skill not recognised (fallback)         | **Given** the first real run shows Claude does not load skills from the personal folder **When** the fix is applied **Then** the prompt changes to tell Claude to read and follow the installed skill file **And** the fix is delivered by a new commit on the PR, never by re-running the old run | Loading of personal-folder skills is supported by the action's defaults but unproven; a re-run reuses the old workflow version and would not pick up the fix                                          | EP   |

---

## 5. Knowing which review round this is

The skill reviews exhaustively the first time and only checks resolutions afterwards; it must tell the two apart without a human.

| Requiriment | Scenario                                      | Expression                                                                                                                                                                                                                                                                                                                          | Complement                                                                                                                                   | Path |
| ----------- | --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ---- |
| FR-020      | Own identity without asking GitHub "who am I" | **When** the skill or its posting script needs its own account name **Then** it takes it from configuration, defaulting to the GitHub Actions bot account **And** it never calls the "current user" endpoint                                                                                                                        | Bot tokens cannot call the "current user" endpoint; the original skill aborted there                                                         | SP   |
| FR-021      | First review on a PR                          | **Given** the PR has no earlier review that is both by the bot account and carries the review marker **When** the skill starts **Then** it runs a full first-round review                                                                                                                                                           | Round 1 must cover everything at once                                                                                                        | SP   |
| FR-022      | Later review on a PR                          | **Given** the PR has N earlier reviews that are both by the bot account and carry the review marker **When** the skill starts **Then** it runs round N+1, checking earlier findings and only new blockers since the commit the latest of those reviews judged **And** reviews by the bot account without the marker are not counted | Other automations also post as the bot account; the marker separates this skill's reviews from theirs so reviews converge instead of growing | SP   |
| FR-023      | Fourth round and beyond                       | **Given** the computed round is four or higher **When** the skill posts **Then** the review holds only the resolution table and new blockers **And** nothing of lower severity is raised                                                                                                                                            | The base skill refuses a fourth round, but in CI every push starts one; the author still sees status on each push without new fronts         | SP   |
| FR-024      | Job re-run after a review was posted          | **Given** a review was already posted for the PR **When** the job is re-run **Then** the new review is treated as the next round, not a fresh first round                                                                                                                                                                           | Re-running to dodge a rate limit must not reopen every finding                                                                               | SP   |

---

## 6. Posting the review

| Requiriment | Scenario                            | Expression                                                                                                                                                                                                                                                                                       | Complement                                                                                                                                                                          | Path |
| ----------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- |
| FR-025      | Explicit target                     | **When** the posting script runs **Then** it posts to the PR number and repository it is given **And** it refuses to run, with a usage message, when either is missing                                                                                                                           | In CI the checkout is a detached merge commit, so "the current branch's PR" does not exist                                                                                          | EP   |
| FR-026      | Review marker                       | **When** a review is posted **Then** its body ends with the hidden review marker, including when a fallback footer was added                                                                                                                                                                     | Later reviews count only marked bot reviews to know which round they are in                                                                                                         | SP   |
| FR-027      | Approve or request-changes rejected | **Given** GitHub rejects a review whose verdict is approve or request-changes, for any reason **When** the script posts **Then** it retries exactly once as a plain comment **And** the comment ends with a footer naming the intended verdict and saying GitHub rejected it for this repository | Repositories that do not let Actions approve PRs still get the review content and the verdict in words; no official source gives the error code, so the retry does not depend on it | EP   |
| FR-028      | Comment verdict rejected            | **Given** GitHub rejects a plain-comment review **When** the script posts **Then** it does not retry **And** exits with a failure naming the comment anchors it sent                                                                                                                             | A rejected comment is usually an anchor on a line outside the diff; retrying the same payload cannot succeed                                                                        | EP   |
| FR-029      | Retry also rejected                 | **Given** the single comment retry is also rejected **Then** the script exits with a failure carrying GitHub's message **And** no further attempt is made                                                                                                                                        | Bounded retries; the job log carries the cause                                                                                                                                      | EP   |
| FR-030      | Noise gate fails                    | **Given** the review content fails the deterministic noise gate **Then** nothing is posted **And** the script exits with a failure saying it refused to post                                                                                                                                     | A review that breaks the skill's quality rules must never reach the PR                                                                                                              | EP   |
| FR-031      | PR authored by the bot itself       | **Given** the PR author is the same account that posts the review **When** the verdict is approve or request-changes **Then** the review is posted as a comment with a footer stating the intended verdict                                                                                       | GitHub forbids approving or rejecting your own PR                                                                                                                                   | EP   |
| FR-032      | Unattended failure                  | **Given** any precondition fails (GitHub CLI unauthenticated, PR not found, posting rejected) **Then** the skill stops and reports the reason in its output **And** never asks anyone to act                                                                                                     | Nobody is watching a CI run; a question would hang until the turn cap                                                                                                               | EP   |
| FR-033      | Picked token rate-limited           | **Given** the picked token is rate-limited or expired **When** Claude starts **Then** the job fails with the action's error **And** no other token is tried in the same run                                                                                                                      | Deliberate: no state, no fallback logic; a manual re-run picks again                                                                                                                | EP   |

---

## 7. Faithfulness to the base skill

| Requiriment | Scenario                   | Expression                                                                                                                                                                                                                                                                                           | Complement                                                                               | Path |
| ----------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ---- |
| FR-034      | Review judgement unchanged | **Then** the review passes, the verification pass, the noise-gate rules, the reference guides and the round-convergence contract are identical to the base skill **And** only the parts that needed a human, a local branch, a working-directory-relative script path or the fourth-round ban differ | The owner wanted the base skill's judgement, adapted only where CI cannot supply a human | SP   |

---

## 8. Setup and maintenance guide

| Requiriment | Scenario                       | Expression                                                                                                                                                                                                                                                                                                                                                               | Complement                                                                                      | Path |
| ----------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- | ---- |
| FR-035      | One-time setup                 | **Then** the guide lists: generating a long-lived token per Claude account, the token-list secret per adopting repository, the permissions block in the adopting job, allowing Actions to approve PRs per adopting repository, and creating the release tag                                                                                                              | Adding a repository must need no rediscovery                                                    | SP   |
| FR-036      | Keeping the skill copy in sync | **Then** the guide describes how to re-copy the skill from its source **And** lists every way the CI copy differs from the source                                                                                                                                                                                                                                        | The copy does not update itself; without the list, a re-copy silently undoes the CI adaptations | SP   |
| FR-037      | Expiry and risk notes          | **Then** the guide states that Claude tokens expire after one year, that multi-account subscription use in CI needs confirmation of the terms of use, that unrestricted shell access lets a PR author with push rights reach the tokens, that no project dependencies are installed before the review, and that a review uses far more plan quota than a one-shot prompt | These are the owner's ongoing obligations and accepted risks; none is enforced by code          | SP   |

---

## 9. Proof of delivery

| Requiriment | Scenario                 | Expression                                                                                                                                                                                                                                    | Complement                                                                      | Path |
| ----------- | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ---- |
| NR-001      | Workflow files are valid | **Then** both workflow files pass the GitHub Actions linter at a pinned version **And** every setting named in this table is asserted by value in an automated test                                                                           | A workflow mistake only shows on GitHub; static checks catch most before a push | SP   |
| NR-002      | End-to-end smoke run     | **Given** a test repository that adopted the review with real tokens **When** a PR is opened and then receives a second commit **Then** both runs succeed **And** two marked bot reviews exist **And** the second contains a resolution table | Skill loading from the personal folder can only be settled by a real run        | SP   |

---

## 10. Accepted consequences (not defects)

Each behaviour below is correct per row but carries a cost the owner accepted.

| #   | Consequence                                                                                                                                                                                                                                      | Driven by              |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------- |
| 1   | The workflow and the CI skill are readable by anyone; the design is safe only while the shared repository holds zero secrets.                                                                                                                    | FR-008, FR-010         |
| 2   | Every adopting repository needs one secret and one permissions block set by hand, plus a repository setting if approvals must show as approvals.                                                                                                 | FR-002, FR-003, FR-035 |
| 3   | Any collaborator with push rights can make the review run their code with unrestricted shell access and read the Claude token and the GitHub token from the process. Restricting the shell would empty the "checks run" section of every review. | FR-017, FR-037         |
| 4   | A rate-limited token fails the whole run; recovery is a manual re-run, and with N tokens a re-run hits the same token with probability 1/N.                                                                                                      | FR-012, FR-033         |
| 5   | Fork PRs and Dependabot PRs never get a review.                                                                                                                                                                                                  | FR-005, FR-006         |
| 6   | Reviews come from the GitHub Actions bot; where Actions may not approve PRs, every clean review appears as a comment with the verdict in a footer instead of an approval.                                                                        | FR-018, FR-027         |
| 7   | Every push after the third review still spends quota on a short resolution-only review; there is no cap on rounds.                                                                                                                               | FR-023                 |
| 8   | The CI skill is a diverging copy: fixes to the source skill reach CI only after a deliberate re-copy and tag move, and each re-copy must re-apply the listed adaptations.                                                                        | FR-034, FR-036         |
| 9   | The shared workflow always fetches the skill at one fixed release tag, so an adopting repository calling any other tag or branch still gets the skill from that fixed tag.                                                                       | FR-009                 |
| 10  | No project dependencies are installed before the review, so repository checks that need them fail and the review reports that failure instead of results.                                                                                        | FR-017, FR-037         |
| 11  | Cancelled runs (newer push) spend quota that produces no review.                                                                                                                                                                                 | FR-007                 |
| 12  | Skill loading from the personal folder is proven only by the smoke run; until then the feature is unproven end to end.                                                                                                                           | FR-016, FR-019, NR-002 |

---

## Glossary

- **FR** — functional requirement
- **NR** — non-functional requirement
- **SP** — success path
- **EP** — error path
- **PR** — pull request
- **Review marker** — a hidden HTML comment appended to every review this skill posts, used to count earlier rounds
- **Shared repository** — the one public repository holding the reusable workflow and the review skill
- **Adopting repository** — any repository that calls the shared workflow

---

## Spec traceability

Maps each row to the spec requirement it derives from, for auditors; reviewers can ignore it.

| Row                            | Spec requirement          |
| ------------------------------ | ------------------------- |
| FR-001                         | CCR-01                    |
| FR-002, FR-003                 | CCR-02                    |
| FR-004                         | CCR-19                    |
| FR-005                         | CCR-20                    |
| FR-006                         | CCR-21                    |
| FR-007                         | CCR-22                    |
| FR-008                         | CCR-25                    |
| FR-009                         | CCR-23                    |
| FR-010                         | CCR-24                    |
| FR-011                         | CCR-06                    |
| FR-012                         | CCR-07                    |
| FR-013                         | CCR-08                    |
| FR-014                         | CCR-09                    |
| FR-015                         | CCR-10                    |
| FR-016                         | CCR-03                    |
| FR-017                         | CCR-04                    |
| FR-018                         | CCR-05                    |
| FR-019                         | CCR-01 (design fallback)  |
| FR-020                         | CCR-11                    |
| FR-021                         | CCR-14                    |
| FR-022, FR-024                 | CCR-13                    |
| FR-023                         | CCR-29                    |
| FR-025                         | CCR-16                    |
| FR-026                         | CCR-12                    |
| FR-027                         | CCR-15                    |
| FR-028, FR-029, FR-030, FR-032 | CCR-17                    |
| FR-031, FR-034                 | CCR-18                    |
| FR-033                         | Edge case (plan decision) |
| FR-035                         | CCR-26                    |
| FR-036                         | CCR-27                    |
| FR-037                         | CCR-28                    |
| NR-001                         | Build gate (actionlint)   |
| NR-002                         | CCR-01, CCR-13            |
