# ADR-001 – Public central review repository with no secrets

> **Date:** 2026-11-11
> **Status:** Accepted
> **Deciders:** Repository owner

## Context

Claude PR reviews run from one reusable workflow and one review skill kept in a central repository, `Ronnasayd/claude-pr-review`. All the other repositories call it. The owner uses a personal GitHub account with no organization (`gh api user/orgs` returned nothing), so there are no organization secrets and no organization-level Actions access policy.

GitHub's `user` access level for a private repository "allows sharing across user owned private repositories only" ([REST docs](https://docs.github.com/en/rest/actions/permissions#get-the-level-of-access-for-workflows-outside-of-the-repository)). The workflow also checks out the central repository to fetch the skill. A caller's `GITHUB_TOKEN` cannot read a different private repository, so every caller would need a personal access token.

## Decision

The central repository is public and holds no secret of any kind. The Claude tokens (`CLAUDE_TOKENS`) live only in each caller repository and reach the reusable workflow through the caller's explicit `secrets:` block. A called workflow receives secrets only that way ([reusing workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)).

## Considered Alternatives

| Alternative                  | Pros                                                                                                       | Cons                                                                                                                                                                   |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Public central repo (chosen) | Public and private repositories can both adopt it. Each caller needs one secret. There is no PAT to renew. | Anyone can read the workflow and the review skill.                                                                                                                     |
| Private central repo         | The workflow and skill stay hidden.                                                                        | Only the owner's private repositories can call it. Each caller needs a `CI_TEMPLATES_TOKEN` PAT that expires. The repository's Actions access setting must be changed. |

## Consequences

- Making the repository private later breaks every public caller, and private callers would need a PAT secret.
- Safety depends on the invariant that the central repository never holds a secret. Its own workflows must never run on its own PRs with `CLAUDE_TOKENS` (spec CCR-24).

## Related ADRs

- ADR-002 – CI-adapted copy of the-judge
