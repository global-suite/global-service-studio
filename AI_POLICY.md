# AI-Assisted Contribution Policy

AI-assisted contributions are permitted. The human contributor must understand, review, validate and take full responsibility for everything they submit.

## Human responsibility

The human contributor remains fully responsible for:

- The security, correctness and ongoing maintenance of the complete submission.
- Reviewing and validating every change, claim and test result.
- Appropriate licensing and confidence in the provenance of submitted material.
- Explaining and defending the design, implementation and tradeoffs during review.

AI assistance does not transfer authorship, accountability or legal responsibility away from the contributor.

## Disclosure

Disclose material AI assistance used to produce or substantively review any part of a contribution: code, tests, documentation, designs or analysis.

For material assistance, the pull request must state:

1. The tool or model, if known.
2. What the assistance covered.
3. What verification the contributor performed.

Raw prompts and conversation logs are not required.

Trivial formatting, spelling fixes, minor autocomplete and search or navigation do not need disclosure.

## Review and attribution

Maintainers may ask for an explanation, supporting evidence or additional tests. They may reject work that the contributor cannot explain, verify or defend.

AI tools must not receive human attribution: no `Co-Authored-By`, `Reviewed-by`, `Tested-by` or `Signed-off-by` trailers. An optional `Assisted-by` trailer is accepted; the pull request declaration is sufficient.

## Submission quality

Review is based on observable quality, not on whether text or code looks AI-generated. Find the underlying cause before proposing a fix, and prefer the smallest change that solves it.

Unacceptable behavior includes:

- Submitting output the contributor has not reviewed.
- Making claims that cannot be verified, or reporting results that did not occur.
- Inventing APIs, paths, behavior, evidence or test results.
- Masking a symptom instead of fixing its cause.
- Including broad or unrelated changes outside the approved scope.
- Copying output without confidence in its provenance or license compatibility. This applies in particular to song lyrics, Bible text, fonts and media.
- Being unable to explain the change or its consequences.
- Leaving the work of understanding or repairing the submission to maintainers.

## Enforcement

Maintainers may close pull requests and issues that do not meet this policy. Repeated low-quality submissions may lead to restricted participation under the [Code of Conduct](CODE_OF_CONDUCT.md).
