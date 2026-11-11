# Community roadmap

Where to find work that is ready to be picked up, and what "ready" means here. For the order in which the project is being built, see the [roadmap](roadmap.md).

## Start here

**[Every issue currently up for grabs](https://github.com/global-suite/global-service-studio/issues?q=is%3Aissue+is%3Aopen+label%3Aup-for-grabs)**

That link is the list. It is a live query, not a table kept by hand, so it cannot go stale.

## What `up-for-grabs` guarantees

An issue carries this label only when all three are true:

1. **It is scoped.** The problem is stated and the expected behavior is specified.
2. **It is approved.** It also carries `status:approved`, which is what allows a pull request to be opened at all. Without it, CI rejects the pull request before review.
3. **Nobody is on it.** When someone takes the issue, a maintainer removes the label.

An issue without the label is not closed to you. It is usually waiting for information (`status:needs-info`) or for a decision (`status:needs-design`). Comment on it instead of opening a pull request: code written before the decision is usually thrown away.

## Picking one up

1. Comment on the issue that you are taking it.
2. Read the [codebase guide](CODEBASE-GUIDE.md) to find where the change goes.
3. Open a pull request that links the issue, following [CONTRIBUTING.md](../CONTRIBUTING.md).

If you stop working on it, say so on the issue so that someone else can take it.

## Proposing something that is not listed

Open a [feature request](https://github.com/global-suite/global-service-studio/issues/new?template=feature_request.yml) and wait for a maintainer to approve it before writing code. For a question or an idea that is not concrete yet, use [Discussions](https://github.com/global-suite/global-service-studio/discussions).

## Other ways to help

- Test a build on an Intel Mac or on macOS 13 and report what you see. The project has few of these machines.
- Improve the Spanish translation, or offer to maintain another language. See [localization.md](localization.md).
- Report a bug with the [bug report form](https://github.com/global-suite/global-service-studio/issues/new?template=bug_report.yml).
