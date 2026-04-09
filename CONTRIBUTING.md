# Contributing to llm_optimizer

Thanks for taking the time to contribute. This document covers everything you need to get set up, raise issues, and submit pull requests.

## Table of Contents

- [Setting Up the Repo](#setting-up-the-repo)
- [Running Tests and Linting](#running-tests-and-linting)
- [Pre-commit Hooks with Overcommit](#pre-commit-hooks-with-overcommit)
- [Raising an Issue](#raising-an-issue)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Code Style](#code-style)
- [Commit Message Guidelines](#commit-message-guidelines)

---

## Setting Up the Repo

**1. Fork the repository**

Click "Fork" on [github.com/arunkumarry/llm_optimizer](https://github.com/arunkumarry/llm_optimizer).

**2. Clone your fork**

```bash
git clone https://github.com/<your-username>/llm_optimizer.git
cd llm_optimizer
```

**3. Add the upstream remote**

```bash
git remote add upstream https://github.com/arunkumarry/llm_optimizer.git
```

**4. Install dependencies**

```bash
bundle install
```

**5. Verify everything works**

```bash
bundle exec rake test
bundle exec rubocop
```

Both should pass before you start making changes.

---

## Running Tests and Linting

```bash
# Run the full test suite
bundle exec rake test

# Run RuboCop
bundle exec rubocop

# Run both (default rake task)
bundle exec rake
```

Add tests for any new behaviour you introduce. Tests live in `test/unit/`.

---

## Pre-commit Hooks with Overcommit

This repo uses [overcommit](https://github.com/sds/overcommit) to run RuboCop and the test suite before every commit.

**Install the hooks after cloning:**

```bash
bundle exec overcommit --install
bundle exec overcommit --sign
```

Every `git commit` will now automatically run RuboCop and the test suite. If either fails, the commit is blocked.

**Bypass for a WIP commit:**

```bash
git commit --no-verify -m "wip: work in progress"
```

Re-enable checks before opening a PR — all hooks must pass.

**Note on rebasing:** If overcommit hooks cause issues during `git pull --rebase`, uninstall them first:

```bash
bundle exec overcommit --uninstall
git pull --rebase origin main
bundle exec overcommit --install
bundle exec overcommit --sign
```

---

## Raising an Issue

Search [existing issues](https://github.com/arunkumarry/llm_optimizer/issues) before opening a new one.

**Bug reports should include:**
- Ruby version (`ruby -v`)
- Gem version (`bundle exec gem list llm_optimizer`)
- Minimal reproduction script
- Expected vs actual behaviour
- Full error message and backtrace

**Feature requests should include:**
- The problem you're solving
- What the API should look like
- Alternatives you've considered

Use labels: `bug`, `enhancement`, `question`, or `documentation`.

---

## Submitting a Pull Request

**1. Sync with upstream before starting**

```bash
git fetch upstream
git rebase upstream/main
```

**2. Create a branch**

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/issue-description
```

Branch naming:
- `feature/` — new functionality
- `fix/` — bug fixes
- `docs/` — documentation only
- `refactor/` — no behaviour change
- `test/` — test additions or fixes

**3. Make your changes**

- Write tests for new behaviour — PRs without tests won't be merged
- Keep changes focused — one concern per PR
- Update `CHANGELOG.md` under `[Unreleased]`

**4. Ensure all checks pass**

```bash
bundle exec rake
```

**5. Push and open a PR**

```bash
git push origin feature/your-feature-name
```

Open a PR against `main` on GitHub.

**PR description should include:**
- What the PR does and why
- Link to the related issue (`Closes #42`)
- How to test it manually if applicable
- Any breaking changes clearly called out

**PR checklist:**
- [ ] Tests added or updated
- [ ] `bundle exec rake` passes locally
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] No unrelated changes included

---

## Code Style

RuboCop is configured in `.rubocop.yml`. Run before committing:

```bash
bundle exec rubocop

# Auto-fix safe offenses
bundle exec rubocop -a
```

Key conventions:
- Double-quoted strings
- `# frozen_string_literal: true` in every file
- No monkey-patching without explicit opt-in
- Errors handled gracefully — never let the optimizer break the app

---

## Commit Message Guidelines

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <short description>

[optional body explaining why]

[optional footer: Closes #issue]
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

Examples:
```
feat: add embedding_caller config for custom providers
fix: handle nil model in raw_llm_call fallback
docs: update README with per-call config example
test: add negative scenarios for SemanticCache lookup
chore: add overcommit pre-commit hooks
```

Subject line under 72 characters. Body explains *why*, not *what*.

---

## Questions?

Open a [GitHub Discussion](https://github.com/arunkumarry/llm_optimizer/discussions) or file an issue with the `question` label.
