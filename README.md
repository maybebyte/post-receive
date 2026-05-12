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

Local verification also needs `prove`. The TAP suite supplies temporary
workspaces, an isolated `HOME`, temporary webroot and sysadm targets,
fake helper commands where needed, bare repository fixtures, and
captured stdout and stderr. Those fakes make local tests safe; they are
not production substitutes.

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

Check the hook syntax with:

```sh
perl -c bin/post-receive
```

Run the supported repository-root test command with:

```sh
prove -lr t
```

For focused diagnostics, run a single TAP file from the repository root,
such as:

```sh
prove -v t/03-website-md.t
prove -v t/04-deployment-branches.t
```

Passing local tests proves contained behavior through temporary fixtures
and fake helpers. It does not prove live OpenBSD deployment, real
`stagit` page output, real `ssg6` or `rssg` output quality, production
ownership or permissions, web-server integration, service integration,
or safety of manual runs against production paths.

## Make safe changes

Change one behavior at a time and rerun `prove -lr t` after each change.
Treat the web root, the sysadm target, and `$HOME/.local/bin` helpers as
dangerous surfaces whenever you edit deployment behavior.

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

The proof boundary is intentionally local: TAP tests exercise the real
hook under contained paths, but they do not validate host ownership,
production permissions, web-server behavior, service behavior, or the
quality of real helper output.

## Project layout

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
- `t/lib/PostReceive/TestHarness.pm` — test load-path compatibility
  shim.

## Further reading

Agent-specific repository guidance lives in [AGENTS.md](AGENTS.md).

A Git `post-receive` hook runs after refs are updated in a bare
repository; see the official Git hooks documentation for general hook
mechanics: https://git-scm.com/docs/githooks
