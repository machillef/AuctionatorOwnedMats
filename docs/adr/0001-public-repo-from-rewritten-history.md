# 1. Publish from a new repository with rewritten history

Date: 2026-11-21. Status: accepted.

## Context

The addon was developed in a private repository. Commits and merged pull requests carried
author emails that should not be public. A history rewrite with a force push cannot clean the
`refs/pull/*/head` refs: GitHub keeps them, and the original commits stay reachable through
the old pull requests.

## Decision

The private repository was renamed `AuctionatorOwnedMats-archive` and kept private, with its pull
requests and review comments. A new `AuctionatorOwnedMats` repository was created from a copy of
`main` rewritten with `git filter-repo`, so every author, committer and `Co-authored-by` email
is the one chosen for public use. The code tree is byte-identical to the archived `main`.

## Consequences

- Pull request numbers and review discussions before v1.2.0 exist only in the private archive.
- Clones made before the switch still use the `AuctionatorOwnedMats` URL, which now resolves to the
  public repository, while their objects hold the old commits. Do not push from them: re-clone the
  public repository, or point `origin` at `AuctionatorOwnedMats-archive`.
