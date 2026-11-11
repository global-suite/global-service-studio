// Checks that the skills index in AGENTS.md and the skills folder agree, and
// that every skill has the frontmatter described in docs/skill-style-guide.md.
// Run from the repository root: node .github/scripts/check-skills-index.mjs
import { existsSync, readdirSync, readFileSync } from 'node:fs';

const errors = [];
const agents = readFileSync('AGENTS.md', 'utf8');

// Index rows look like: | `name` | when | [path](skills/name/SKILL.md) |
const indexed = new Map();
for (const match of agents.matchAll(/^\|\s*`([^`]+)`\s*\|[^|]*\|\s*\[[^\]]*\]\((skills\/[^)]+)\)\s*\|\s*$/gm)) {
  indexed.set(match[1], match[2]);
}
if (indexed.size === 0) errors.push('AGENTS.md has no skills index rows.');

const folders = existsSync('skills')
  ? readdirSync('skills', { withFileTypes: true }).filter((entry) => entry.isDirectory()).map((entry) => entry.name)
  : [];

for (const [name, path] of indexed) {
  if (path !== `skills/${name}/SKILL.md`) errors.push(`AGENTS.md: skill "${name}" points to "${path}", expected "skills/${name}/SKILL.md".`);
  if (!existsSync(path)) errors.push(`AGENTS.md: skill "${name}" points to "${path}", which does not exist.`);
}

for (const folder of folders) {
  const path = `skills/${folder}/SKILL.md`;
  if (!indexed.has(folder)) errors.push(`${path}: not listed in the skills index of AGENTS.md.`);
  if (!existsSync(path)) { errors.push(`${path}: missing.`); continue; }

  const text = readFileSync(path, 'utf8');
  const frontmatter = text.match(/^---\n([\s\S]*?)\n---\n/);
  if (!frontmatter) { errors.push(`${path}: no frontmatter block.`); continue; }
  const field = (pattern) => frontmatter[1].match(pattern)?.[1];

  const name = field(/^name:\s*(\S+)\s*$/m);
  const description = field(/^description:\s*"(.*)"\s*$/m);
  if (name !== folder) errors.push(`${path}: name is "${name}", expected "${folder}".`);
  if (description === undefined) errors.push(`${path}: description must be one double-quoted line.`);
  else {
    if (!description.startsWith('Trigger:')) errors.push(`${path}: description must start with "Trigger:".`);
    if (description.length > 250) errors.push(`${path}: description is ${description.length} characters, over 250.`);
  }
  if (!field(/^license:\s*(\S+)\s*$/m)) errors.push(`${path}: license is missing.`);
  if (!field(/^  author:\s*(\S+)\s*$/m)) errors.push(`${path}: metadata.author is missing.`);
  if (!field(/^  version:\s*"([^"]+)"\s*$/m)) errors.push(`${path}: metadata.version must be a quoted string.`);
}

if (errors.length > 0) {
  for (const error of errors) console.error(`FAIL ${error}`);
  console.error(`\n${errors.length} problem(s). See docs/skill-style-guide.md.`);
  process.exit(1);
}
console.log(`${folders.length} skills, index and frontmatter consistent.`);
