# post-receive

This repository contains an executable Perl Git `post-receive` hook
and a local TAP suite. The hook publishes repository metadata and
`stagit` pages, with special deployment behavior for `website_md.git`,
`sysadm.git`, and `dotfiles.git`.

## What the hook does

The hook runs from inside a bare repository and derives the publishing
name from the current directory, minus a trailing `.git` suffix. For
all repositories, it:

- writes `owner`, `description`, and `url` metadata files in the bare
  repository;
- clears and recreates `src/<repo>` under the configured web root;
- clones the bare repository into `src/<repo>/.git`;
- runs `git update-server-info` in that clone;
- runs `stagit -- <repo>` from the repository output directory;
- copies `log.html` to `index.html`;
- copies shared `stagit/style.css`, `stagit/logo.png`, and
  `stagit/favicon.png` into the repository output; and
- writes `.gz` sidecars for generated `html`, `css`, `txt`, `xml`,
  `asc`, and `svg` files larger than 1400 bytes, while skipping paths
  containing `.git`.

Special repositories add a short deployment step before the shared
`stagit` publishing path:

- `website_md.git` rebuilds the site root with
  `$HOME/.local/bin/ssg6` and `$HOME/.local/bin/rssg`, preserves
  `src/` while clearing the web root, writes `rss.xml`, removes the
  generated `.files` marker, gzips eligible site-root output, and then
  publishes `src/website_md`. During that site-root gzip pass, only
  `src/src.html` is eligible beneath `src/`. The hook aborts before
  touching the web root if either helper is missing or not executable,
  naming the offending path on stderr.
- `sysadm.git` clones the repository, clears the sysadm target, moves
  top-level clone entries except `.git` into that target, and then
  publishes `src/sysadm`. The target defaults to `/etc/sysadm` and can
  be overridden with `POST_RECEIVE_SYSADM_DIR`.
- `dotfiles.git` replaces `$HOME/.local/bin/ssg6` from the cloned
  `.local/bin/ssg`, replaces `$HOME/.local/bin/rssg`, resets both
  installed helpers to mode `0700`, and then publishes `src/dotfiles`.

## Requirements

Runtime or deployment hosts need:

- Perl v5.36 or newer;
- the Perl module `IPC::System::Simple`;
- real `git` and `stagit` commands available to the hook;
- shared `stagit` assets at `stagit/style.css`, `stagit/logo.png`, and
  `stagit/favicon.png` under the configured web root;
- `$HOME/.local/bin/ssg6` and `$HOME/.local/bin/rssg` for
  `website_md.git`, which the hook checks up front and refuses to run
  without; `dotfiles.git` installs these helpers in place, so it does
  not require them to pre-exist; and
- a deliberate environment for `POST_RECEIVE_WEB_SERVER_DIR`,
  `POST_RECEIVE_SYSADM_DIR`, and `HOME`.

If `POST_RECEIVE_WEB_SERVER_DIR` is unset, the hook uses
`/var/www/htdocs/www.anthes.is`. If `POST_RECEIVE_SYSADM_DIR` is unset,
it uses `/etc/sysadm`. `HOME` controls both helper lookup and helper
replacement under `.local/bin`.

Local developer verification also needs:

- `make` for the repository quality-gate targets;
- `prove` for the TAP suite;
- `perltidy` for formatting and non-mutating formatting assertions; and
- `Perl::Critic`, available as `perlcritic`, for the lint gate.

These verification tools are developer-only prerequisites for local
checks. They are not production hook runtime dependencies.

The TAP suite supplies temporary workspaces, an isolated `HOME`,
temporary webroot and sysadm targets, fake helper commands where needed,
bare repository fixtures, and captured stdout and stderr. Those fakes
make local tests safe; they are not production substitutes.

## Install or deploy

Before deploying, confirm the target host has the runtime requirements
above and that the configured side-effect paths are the ones you intend
the hook to mutate. Running the hook outside the local harness can clear
and recreate webroot output, clear the sysadm target, and replace helper
binaries under `$HOME/.local/bin`.

Install the executable hook into each bare repository that should
publish through this workflow:

```sh
install -m 0755 bin/post-receive /path/to/repo.git/hooks/post-receive
```

Set `POST_RECEIVE_WEB_SERVER_DIR` when the publish root should not be
`/var/www/htdocs/www.anthes.is`. Set `POST_RECEIVE_SYSADM_DIR` when
`sysadm.git` should not deploy into `/etc/sysadm`. Set `HOME` to the
account whose `.local/bin` helpers should be used or updated.

## Verify locally

From the repository root, run the supported local quality gate with:

```sh
make check
```

`make check` runs the hook syntax check, the configured Perl::Critic
lint gate, non-mutating perltidy formatting assertions, the `.bak`
backup-file guard, and the full TAP proof.

When a gate fails, narrow it with the direct command for that layer:

```sh
perl -c bin/post-receive
make lint
perlcritic bin lib t
make tidy-check
make no-backups
prove -lr t
```

For focused TAP diagnostics, run a single TAP file from the repository
root, such as:

```sh
prove -v t/03-website-md.t
prove -v t/04-deployment-branches.t
```

Passing local `make check` or TAP evidence proves contained behavior
through temporary fixtures and fake helpers. It does not prove live
OpenBSD deployment, real `stagit`, `ssg6`, or `rssg` output quality,
production ownership or permissions, web-server integration, service
integration, or production path safety.

## Make safe changes

Change one behavior at a time. For behavior changes, use
red-green-refactor: add or update the failing behavior-focused TAP
expectation, make the smallest hook change, then refactor only after the
focused proof is green. For behavior-preserving refactors, tie the edit
to existing green TAP coverage.

While iterating, run the focused TAP file that owns the behavior, for
example `prove -v t/03-website-md.t`. Before claiming completion, run
`make check` so syntax, lint, formatting assertions, backup detection,
and the full TAP suite all pass through the same quality gate.

Treat the web root, the sysadm target, and `$HOME/.local/bin` helpers as
dangerous surfaces whenever you edit deployment behavior.

Run `perltidy -b` on every Perl file you touch before staging it. The
repo-root `.perltidyrc` supplies the shared style, so any `perltidy`
invocation inside the tree picks it up. Remove the `.bak` files
`perltidy` writes before committing, or use `make no-backups` to catch
leftover backup artifacts.

Use the TAP files as ownership guides:

- `t/00-baseline.t` checks hook presence, executable mode, and
  `perl -c`.
- `t/01-harness-common.t` checks harness mechanics and the generic hook
  path.
- `t/02-shared-publishing.t` checks shared publishing and gzip behavior.
- `t/03-website-md.t` checks `website_md.git` behavior and site-root
  gzip rules.
- `t/04-deployment-branches.t` checks `sysadm.git`, `dotfiles.git`,
  helper replacement, and append validation.
- `t/05-dependency-checks.t` checks fail-fast helper dependency errors
  for `website_md.git` before destructive side effects.

The proof boundary is intentionally local: `make check` and TAP tests
exercise the real hook under contained paths and fake helpers. They do
not prove live OpenBSD deployment, real `stagit`, `ssg6`, or `rssg`
output quality, production ownership or permissions, web-server
integration, service integration, or production path safety.

## Project layout

- `Makefile` — local quality gate and focused targets for syntax,
  Perl::Critic lint, formatting assertions, backup detection, and TAP
  tests.
- `.perlcriticrc` — developer-only Perl::Critic baseline for
  `perlcritic bin lib t`.
- `.perltidyrc` — shared `perltidy` style applied to every clone.
- `bin/post-receive` — executable hook entrypoint.
- `lib/PostReceive/TestHarness.pm` — containment harness used by local
  tests.
- `t/00-baseline.t` — file, mode, and syntax checks.
- `t/01-harness-common.t` — common harness and generic hook checks.
- `t/02-shared-publishing.t` — shared `stagit` publishing and gzip
  checks.
- `t/03-website-md.t` — `website_md.git` website generation checks.
- `t/04-deployment-branches.t` — `sysadm.git` and `dotfiles.git`
  deployment checks.
- `t/05-dependency-checks.t` — `website_md.git` helper dependency
  fail-fast checks.
- `t/lib/PostReceive/TestHarness.pm` — test load-path compatibility
  shim.

## Further reading

Agent-specific repository guidance lives in [AGENTS.md](AGENTS.md).
