# Agent Guide

## Commands

- Syntax check the production hook with `perl -c bin/post-receive`.
- Run the supported local proof with `prove -lr t` from the repository root.
- For focused diagnostics, use `prove -v t/03-website-md.t` or another single TAP file, then rerun `prove -lr t` before claiming the full local proof.
- Passing TAP output proves contained local behavior through temporary fixtures and fake helpers only. It does not prove live deployment, real `stagit`, `ssg6`, or `rssg` output quality, host ownership or permissions, web-server integration, service integration, or production path safety.

## Project map

- `README.md` is the human overview for behavior, requirements, deployment warnings, verification commands, proof limits, and layout.
- `bin/post-receive` is the self-contained production Git hook. Keep production behavior in this single-file hook; do not extract production modules.
- `lib/PostReceive/TestHarness.pm` is test-only support for contained TAP runs, fake commands, temporary repositories, and captured diagnostics.
- `t/` owns behavior-focused TAP coverage for the hook, including baseline checks, harness mechanics, shared publishing, website generation, and deployment-branch behavior.

## Boundaries

- Keep agent guidance portable: depend only on committed repository files and repository-root commands.
- Treat `prove -lr t` as a local behavior proof, not a live OpenBSD or production deployment proof.
- Preserve the single-file hook boundary unless the README and tests first justify a behavior-changing redesign.
- Do not require local dotfiles, generated state, untracked setup, or machine-specific paths.

## Change rules

- Change one behavior at a time and cover behavior changes with behavior-focused TAP tests.
- For features, use red-green-refactor: add or update the failing TAP expectation, make the smallest hook change, then refactor after green.
- Refactor anchor rule: tie every refactor to existing green tests when behavior is unchanged, or to a failing behavior test when behavior changes.
- Update `README.md` when behavior, runtime requirements, deployment expectations, verification commands, proof limits, or project layout changes.
- Prefer comments that explain WHY a constraint exists over WHAT the next line already says.
