// Regression test for the scripts in .github/workflows/pr-policy.yml.
// Dependency-free: run with `node .github/scripts/test-pr-policy.mjs`.
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const workflowPath = new URL('../workflows/pr-policy.yml', import.meta.url);
const lines = readFileSync(workflowPath, 'utf8').split('\n');

// Extract every `script: |` block by indentation.
const scripts = [];
for (let i = 0; i < lines.length; i++) {
  const header = lines[i].match(/^(\s*)script: \|\s*$/);
  if (!header) continue;
  const block = [];
  let j = i + 1;
  for (; j < lines.length; j++) {
    const line = lines[j];
    if (line.trim() !== '' && line.match(/^\s*/)[0].length <= header[1].length) break;
    block.push(line);
  }
  const indent = Math.min(...block.filter((l) => l.trim()).map((l) => l.match(/^\s*/)[0].length));
  scripts.push(block.map((l) => l.slice(indent)).join('\n'));
  i = j - 1;
}
if (scripts.length !== 3) {
  console.error(`FAIL: expected exactly 3 script blocks in pr-policy.yml, found ${scripts.length}`);
  process.exit(1);
}
const [linkedIssueScript, typeLabelScript, sizeScript] = scripts;

const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor;
const OWNER = 'global-suite';
const REPO = 'global-service-studio';

async function run(src, { pr, issues = {} }) {
  const result = { failed: [], warnings: [], infos: [] };
  const github = {
    rest: {
      pulls: { get: async () => ({ data: { body: '', labels: [], additions: 0, deletions: 0, ...pr } }) },
      issues: {
        get: async ({ issue_number }) => {
          if (!(issue_number in issues)) {
            const error = new Error('Not Found');
            error.status = 404;
            throw error;
          }
          return { data: issues[issue_number] };
        },
      },
    },
  };
  const context = { repo: { owner: OWNER, repo: REPO }, payload: { pull_request: { number: 99 } } };
  const core = {
    setFailed: (m) => result.failed.push(m),
    warning: (m) => result.warnings.push(m),
    info: (m) => result.infos.push(m),
  };
  await new AsyncFunction('github', 'context', 'core', src)(github, context, core);
  return result;
}

const approved = { labels: [{ name: 'status:approved' }] };
const notApproved = { labels: [{ name: 'status:needs-review' }] };
const labels = (...names) => names.map((name) => ({ name }));

const cases = [
  // Linked approved issue
  ['issue: no keyword', linkedIssueScript, { pr: { body: 'Implements #5' }, issues: { 5: approved } }, 'fail'],
  ['issue: empty body', linkedIssueScript, { pr: { body: '' }, issues: { 5: approved } }, 'fail'],
  ['issue: null body', linkedIssueScript, { pr: { body: null }, issues: { 5: approved } }, 'fail'],
  ['issue: Closes #5 not approved', linkedIssueScript, { pr: { body: 'Closes #5' }, issues: { 5: notApproved } }, 'fail'],
  ['issue: Closes #5 approved', linkedIssueScript, { pr: { body: 'Closes #5' }, issues: { 5: approved } }, 'pass'],
  ['issue: Fixes: #5', linkedIssueScript, { pr: { body: 'Fixes: #5' }, issues: { 5: approved } }, 'pass'],
  ['issue: resolved #5', linkedIssueScript, { pr: { body: 'resolved #5' }, issues: { 5: approved } }, 'pass'],
  ['issue: reference to a pull request', linkedIssueScript,
    { pr: { body: 'Closes #7' }, issues: { 7: { ...approved, pull_request: {} } } }, 'fail'],
  ['issue: cross-repo only', linkedIssueScript, { pr: { body: 'Closes other/repo#5' }, issues: { 5: approved } }, 'fail'],
  ['issue: same repo, owner/repo form, mixed case', linkedIssueScript,
    { pr: { body: 'closes Global-Suite/Global-Service-Studio#5' }, issues: { 5: approved } }, 'pass'],
  ['issue: keyword only in HTML comment', linkedIssueScript,
    { pr: { body: '<!-- Closes #5 -->' }, issues: { 5: approved } }, 'fail'],
  ['issue: missing issue (404)', linkedIssueScript, { pr: { body: 'Closes #6' }, issues: {} }, 'fail'],
  ['issue: one approved and one not', linkedIssueScript,
    { pr: { body: 'Closes #5\nCloses #6' }, issues: { 5: approved, 6: notApproved } }, 'pass', 'warning'],
  ['issue: disclosed #5', linkedIssueScript, { pr: { body: 'disclosed #5' }, issues: { 5: approved } }, 'fail'],
  ['issue: Closes #5abc', linkedIssueScript, { pr: { body: 'Closes #5abc' }, issues: { 5: approved } }, 'fail'],
  ['issue: full URL, this repository', linkedIssueScript,
    { pr: { body: `Closes https://github.com/${OWNER}/${REPO}/issues/5` }, issues: { 5: approved } }, 'pass'],
  ['issue: full URL, other repository', linkedIssueScript,
    { pr: { body: 'Closes https://github.com/other/repo/issues/5' }, issues: { 5: approved } }, 'fail'],
  ['issue: Closes#5', linkedIssueScript, { pr: { body: 'Closes#5' }, issues: { 5: approved } }, 'pass'],
  ['issue: only in fenced code block', linkedIssueScript,
    { pr: { body: 'Example:\n```\nCloses #5\n```\n' }, issues: { 5: approved } }, 'fail'],
  ['issue: only in inline code', linkedIssueScript,
    { pr: { body: 'Write `Closes #5` in the body.' }, issues: { 5: approved } }, 'fail'],
  ['issue: inline ```code``` at line start, real link after', linkedIssueScript,
    { pr: { body: '```npm test``` passes\nCloses #6' }, issues: { 6: approved } }, 'pass'],
  ['issue: fenced #5 ignored, real #6 linked', linkedIssueScript,
    { pr: { body: 'x\n```\nCloses #5\n```\nCloses #6' }, issues: { 5: notApproved, 6: approved } }, 'pass'],
  // An unclosed fence hides nothing: guessing where it ends rejects valid bodies.
  ['issue: unclosed fence hides nothing', linkedIssueScript,
    { pr: { body: 'text\n```\nCloses #5\nmore' }, issues: { 5: approved } }, 'pass'],
  ['issue: fence inside a list item', linkedIssueScript,
    { pr: { body: '- ```\n  npm test\n  ```\n\nCloses #6' }, issues: { 6: approved } }, 'pass'],
  ['issue: fence left open inside details', linkedIssueScript,
    { pr: { body: '<details>\n```\nlog\n</details>\n\nCloses #6' }, issues: { 6: approved } }, 'pass'],
  ['issue: escaped backtick is not inline code', linkedIssueScript,
    { pr: { body: '\\`a Closes #6 `b`' }, issues: { 6: approved } }, 'pass'],
  ['issue: tilde fence', linkedIssueScript,
    { pr: { body: '~~~\nCloses #5\n~~~\n' }, issues: { 5: approved } }, 'fail'],
  ['issue: CRLF body with fence', linkedIssueScript,
    { pr: { body: '```\r\nCloses #5\r\n```\r\nResolves #6\r\n' }, issues: { 5: notApproved, 6: approved } }, 'pass'],
  ['issue: tilde fence showing a backtick fence opener, real link after', linkedIssueScript,
    { pr: { body: 'Example:\n~~~markdown\n```js\n~~~\n\nCloses #6' }, issues: { 6: approved } }, 'pass'],
  ['issue: ```js line inside a fence does not close it', linkedIssueScript,
    { pr: { body: '```\nx\n```js\nCloses #5\n```' }, issues: { 5: approved } }, 'fail'],
  ['issue: ``` does not close ````', linkedIssueScript,
    { pr: { body: '````\n```\nCloses #5\n````' }, issues: { 5: approved } }, 'fail'],
  ['issue: ~~~ not closed by ```', linkedIssueScript,
    { pr: { body: '~~~\nCloses #5\n```\n~~~' }, issues: { 5: approved } }, 'fail'],
  ['issue: CRLF inline code at line start', linkedIssueScript,
    { pr: { body: '```npm test``` ok\r\nCloses #6\r\n' }, issues: { 6: approved } }, 'pass'],
  ['issue: fence indented 3 spaces', linkedIssueScript,
    { pr: { body: '   ```\nCloses #5\n   ```\nCloses #6' }, issues: { 5: notApproved, 6: approved } }, 'pass'],
  ['issue: URL to a pull request', linkedIssueScript,
    { pr: { body: `Closes https://github.com/${OWNER}/${REPO}/pull/5` }, issues: { 5: approved } }, 'fail'],

  // Exactly one type label
  ['type: zero labels', typeLabelScript, { pr: { labels: [] } }, 'fail'],
  ['type: one valid label', typeLabelScript, { pr: { labels: labels('type:bug', 'priority:low') } }, 'pass'],
  ['type: two labels', typeLabelScript, { pr: { labels: labels('type:bug', 'type:docs') } }, 'fail'],
  ['type: only unknown type:foo', typeLabelScript, { pr: { labels: labels('type:foo') } }, 'fail'],
  ['type: type:bug and type:foo', typeLabelScript, { pr: { labels: labels('type:bug', 'type:foo') } }, 'fail'],

  // PR size budget
  ['size: 0 lines', sizeScript, { pr: { additions: 0, deletions: 0 } }, 'pass'],
  ['size: 400 lines', sizeScript, { pr: { additions: 300, deletions: 100 } }, 'pass'],
  ['size: 401 lines', sizeScript, { pr: { additions: 301, deletions: 100 } }, 'fail'],
  ['size: 401 lines with size:exception', sizeScript,
    { pr: { additions: 301, deletions: 100, labels: labels('size:exception') } }, 'pass', 'warning'],
];

let failures = 0;
for (const [name, src, input, expected, expectWarning] of cases) {
  try {
    const result = await run(src, input);
    const outcome = result.failed.length > 0 ? 'fail' : 'pass';
    assert.equal(outcome, expected, `expected ${expected}, got ${outcome} ${JSON.stringify(result.failed)}`);
    if (expectWarning) assert.ok(result.warnings.length > 0, 'expected a warning');
    if (name === 'type: only unknown type:foo' || name === 'type: type:bug and type:foo') {
      assert.match(result.failed.join('\n'), /type:foo/, 'failure message must name type:foo');
    }
    console.log(`ok   ${name}`);
  } catch (error) {
    failures++;
    console.log(`FAIL ${name}: ${error.message.split('\n')[0]}`);
  }
}

console.log(`\n${cases.length - failures}/${cases.length} cases passed`);
process.exit(failures === 0 ? 0 : 1);
