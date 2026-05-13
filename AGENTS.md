# Agent Guide

## Commands

- Run `make check` from the repository root as the default local quality gate. It routes through `syntax`, `lint`, `tidy-check`, `no-backups`, and `test`.
- `make check` covers `perl -c bin/post-receive`, `perlcritic --profile .perlcriticrc bin lib t`, non-mutating perltidy assertions, backup-artifact detection, and `prove -lr t`.
- Use targeted diagnostics when a gate fails:
  - `perl -c bin/post-receive` checks production-hook syntax directly.
  - `make lint` runs the configured strict Perl::Critic profile; `perlcritic --profile .perlcriticrc bin lib t` shows direct Perl::Critic output.
  - `make tidy-check` reruns only the non-mutating formatting assertions.
  - `make no-backups` reruns only the `.bak` artifact guard.
  - `prove -v t/03-website-md.t` or another single TAP file narrows test failures before rerunning `prove -lr t` or `make check`.
- Format touched Perl with `perltidy -b <file>` before commit. Tidy every staged `.pl`/`.pm`/`.t` file and `bin/post-receive`, then run `make tidy-check` to assert formatting and `make no-backups` or delete `.bak` artifacts before staging.
- Missing `perlcritic` or `perltidy` reports a developer-tool setup failure from the Make targets. `Perl::Critic` and perltidy are local verification prerequisites, not production hook runtime dependencies.
- Keep `CLAUDE.md` as the exact `@AGENTS.md` include shim. Verify with `printf '@AGENTS.md\n' | cmp -s - CLAUDE.md` when changing agent guidance.
- Passing `make check` proves contained local behavior through temporary fixtures and fake helpers only. It does not prove live deployment, real `stagit`, `ssg6`, or `rssg` output quality, host ownership or permissions, web-server integration, service integration, or production path safety.

## Project map

- `README.md` is the human overview for behavior, requirements, deployment warnings, verification commands, proof limits, and layout.
- `AGENTS.md` is the canonical portable agent guidance surface; `CLAUDE.md` must remain exactly the `@AGENTS.md` include shim.
- `Makefile` defines the local quality gate and focused targets for syntax, lint, formatting assertions, backup detection, and TAP tests.
- `.perlcriticrc` is the strict developer-only Perl::Critic profile used by `make lint` and `make check`.
- `.perltidyrc` is the shared perltidy style. Tracked at the repo root so every clone formats the same way.
- `bin/post-receive` is the self-contained production Git hook. Keep production behavior in this single-file hook; do not extract production modules.
- `lib/PostReceive/TestHarness.pm` is test-only support for contained TAP runs, fake commands, temporary repositories, and captured diagnostics.
- `t/` owns behavior-focused TAP coverage for the hook, including baseline checks, harness mechanics, shared publishing, website generation, dependency checks in `t/05-dependency-checks.t`, and deployment-branch behavior.

## Boundaries

- Keep agent guidance portable: depend only on committed repository files and repository-root commands.
- Treat `make check` and `prove -lr t` as local behavior proof, not a live OpenBSD or production deployment proof.
- Preserve the single-file `bin/post-receive` hook boundary unless the README and tests first justify a behavior-changing redesign.
- Keep Perl::Critic and perltidy as developer verification tools, not production runtime dependencies.
- Preserve `CLAUDE.md` as exactly the `@AGENTS.md` include shim; do not duplicate or expand guidance there.
- Do not require local dotfiles, generated state, untracked setup, or machine-specific paths.

## Change rules

- Change one behavior at a time and cover behavior changes with behavior-focused TAP tests.
- For features, use red-green-refactor: add or update the failing TAP expectation, make the smallest hook change, then refactor after green.
- Refactor anchor rule: tie every refactor to existing green tests when behavior is unchanged, or to a failing behavior test when behavior changes.
- Update `README.md` when behavior, runtime requirements, deployment expectations, verification commands, proof limits, or project layout changes.
- When touching agent guidance, keep `CLAUDE.md` as the exact include shim and rerun the shim comparison command.
- Prefer comments that explain WHY a constraint exists over WHAT the next line already says.
