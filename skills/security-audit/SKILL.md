---
name: security-audit
description: Scan the user's project directories for compromised npm/pip/cargo packages, check dependency versions against known supply chain attacks, and audit installed packages across the development environment.
allowed-tools: Bash, Read, Grep, Glob, Agent, WebSearch
---

# Supply Chain Security Audit

You are performing a supply chain security audit across the user's development environment.

## Where to scan

The user's project directories aren't hardcoded here (they're personal). Resolve them in order:

1. The dirs listed in `~/.agents/memory/reference_project_dirs.md` and the "Where my work lives" section of `~/.agents/AGENTS.md`.
2. If those don't exist, ask the user for their top-level code/workspace directories.

Then also scan these common stray-install locations under `$HOME`:

- `~/.npm/` — npm cache and npx installs
- `~/.config/` — config-level node packages
- `~/.local/` — local bin packages

## Audit Steps

### Step 1: Discover All Package Ecosystems

For each project directory, recursively find (unlimited depth — monorepos nest deeply):

- **npm/Node.js**: `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `bun.lockb`
- **Python**: `requirements.txt`, `pyproject.toml`, `Pipfile.lock`, `poetry.lock`, `uv.lock`
- **Rust**: `Cargo.lock`
- **Go**: `go.sum`

### Step 2: Extract Installed Versions

For npm, check actual installed versions in `node_modules/`:
```bash
find <dir> -path "*/node_modules/<package>/package.json" | while read f; do
  version=$(grep '"version"' "$f" | head -1 | sed 's/.*: *"//;s/".*//')
  echo "$version  $f"
done
```

For Python:
```bash
pip list --format=json 2>/dev/null
find <dir> -path "*/site-packages/<package>*" -name "METADATA"
```

### Step 3: Check Against Known Compromised Versions

If the user names specific compromised versions/CVEs, check all installs against those exactly. Otherwise:

1. `npm audit` in each project with a `package-lock.json`
2. `pip audit` or `safety check` if available
3. Flag packages with versions that don't exist on the registry (yanked/removed = suspicious)

### Step 4: Check for Suspicious Patterns

- `preinstall` / `postinstall` scripts that execute remote code
- Dependencies recently added and not in the lockfile
- Version ranges using `*` or overly broad ranges like `>=0.0.0`
- `.npmrc` / `.pypirc` with unusual registry URLs

### Step 5: Check Global Installs

```bash
npm list -g --depth=0 2>/dev/null
```

Also check globally installed Python packages in common environments.

## Output Format

| Project | Package | Version | Status |
|---------|---------|---------|--------|
| path    | name    | x.y.z   | Safe / COMPROMISED / Suspicious |

Then: **Summary** (packages scanned, issues found), **Action items** (priority order), **Prevention tips**.

## Arguments

If the user provides specific package names or CVEs, focus the audit on those. Otherwise run a full general audit across all ecosystems.
