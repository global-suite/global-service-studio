# Versions and releases

## Version numbers

Releases follow [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

| Part | Changes when |
|---|---|
| `MAJOR` | A saved file format or the remote API changes in a way that is not backwards compatible |
| `MINOR` | Features are added |
| `PATCH` | Only bugs are fixed |

Until `1.0.0` the project is in initial development: versions are `0.MINOR.PATCH` and a minor release may include breaking changes, which the release notes call out.

## Where changes are recorded

- **Commits and pull request titles** use Conventional Commits. Pull requests are squash-merged, so `main` has one commit per pull request.
- **Release notes** on GitHub are the changelog. Each release has a short descriptive title and groups its changes into features, fixes and breaking changes, each linked to its pull request.

## Tags

| Tag | Meaning |
|---|---|
| `v0.3.0` | A stable release |
| `v0.3.0-rc.1`, `v0.3.0-beta.1` | A pre-release for community testing; marked as pre-release and not offered as an update |

## Release checklist

Releases are cut by the owner.

1. `main` is green in CI.
2. The build is tested on Apple silicon and on an Intel Mac running macOS 13.
3. Files saved by the previous release open correctly.
4. English and Spanish strings are complete.
5. The version number is updated.
6. A tag `vX.Y.Z` is pushed on the release commit.
7. The app is built as a universal binary, signed with Developer ID and notarized.
8. The GitHub release is published with its notes and the signed download.

Steps 7 and 8 will be automated by a release workflow triggered by the tag, once the app target and the signing setup exist. That workflow will refuse to publish if CI was not green on the tagged commit.

## Supported versions

Only the latest release receives fixes. There are no maintenance branches before `1.0.0`.
