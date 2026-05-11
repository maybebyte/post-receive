# post-receive

This directory is the commit-visible in-worktree mirror of the extracted `sysadm` Git `post-receive` hook.

M001 keeps the extracted hook runnable as-is while characterizing its current behavior before any simplification. The original extraction lives outside the milestone worktree as read-only input; this mirror exists so characterization changes and summaries stay isolated, writable, and committable from the milestone worktree. S03 uses the in-worktree `post-receive-extracted/` mirror instead of editing the external extracted source directly, S04 adds contained `website_md.git` branch characterization on top of that mirror, and S05 finishes the remaining `sysadm.git` and `dotfiles.git` deployment-branch coverage plus the fresh-reader handoff map.

## What a fresh reader should do first

1. Read the safety boundary plus the S03, S04, and S05 characterization boundaries below.
2. Run `prove -lr t` from this directory for the full mirror suite.
3. From the milestone worktree root, run `prove -v post-receive-extracted/t/04-deployment-branches.t` when you need the focused `sysadm.git` and `dotfiles.git` branch diagnostic.
4. From the milestone worktree root, run `prove -v post-receive-extracted/t/03-website-md.t` when you need the focused `website_md.git` branch diagnostic.
5. Use the harness-backed tests for runtime characterization instead of running the hook against real host paths.

## S03 characterization boundary

S03 intentionally splits shared publishing characterization into two complementary signals after the worktree-containment replan.

- Live stagit smoke coverage stays with the original extracted-hook line of work that this milestone treats as read-only input. It proves the shared publishing path can still integrate with the real `stagit` binary under isolated temporary HOME, webroot, and repository paths.
- Fake stagit coverage lives in this mirror and proves the deterministic shared publishing gzip and asset-copying contract without depending on version-specific `stagit` HTML output.
- The mirrored fake-stagit path still exercises the real hook as a black box: it removes and recreates the repo-specific output directory, clones the bare repository into `.git`, runs `git update-server-info`, runs `stagit` through the prepended fake shim, copies `log.html` to `index.html`, copies shared `style.css` / `logo.png` / `favicon.png`, and gzips only eligible files above the 1400-byte threshold.
- For this mirror, the supported repo-root verification command remains `prove -lr t`. From the milestone worktree root, run `prove -r post-receive-extracted/t`.

## S04 website_md characterization boundary

S04 adds a contained black-box characterization for the `website_md.git` branch-specific path in this mirror.

- `t/03-website-md.t` proves the current extracted behavior with faked helpers and temporary directories; it does **not** claim that production `ssg6`/`rssg` behavior was exercised or that manual runs against real host paths are safe.
- PATH fakes alone are insufficient for the website helpers. The hook resolves `ssg6` and `rssg` through absolute `$HOME/.local/bin/ssg6` and `$HOME/.local/bin/rssg`, so the test installs those fakes under the harness HOME while fake `stagit` stays a PATH shim for the shared publishing tail.
- The website branch clears the temp webroot root while preserving `src`. That cleanup deletes root-level assets seeded before the run, so the fake `ssg6` helper must recreate root `stagit/style.css`, `stagit/logo.png`, and `stagit/favicon.png` before the shared publishing tail copies them into `src/website_md`.
- The fake `ssg6` helper must avoid stdout. The hook waits for `ssg6` before closing its captured stdout pipe, so a chatty fake can deadlock the child process; trace files and generated fixture content are the safe evidence surface instead.
- The current website gzip rule is intentionally narrow: in `no-src` mode it gzips eligible root files plus `src/src.html`, but it intentionally leaves sibling files such as `src/other.html` uncompressed even when they exceed the 1400-byte threshold.
- `rssg` is the stdout-producing helper for this path: the hook reads its stdout into `rss.xml`, and the test preserves that containment by using deterministic fake RSS output instead of a real helper.

## S05 deployment-branches characterization boundary

S05 adds the contained black-box characterization for the remaining deployment-oriented branch paths while keeping the shared publishing tail visible and deterministic in the same mirror.

- `t/04-deployment-branches.t` is the focused branch test for `sysadm.git` and `dotfiles.git`. It still uses fake `stagit` for the shared publishing tail, so the branch-specific setup stays isolated without forking the generic publishing assertions into separate ad hoc scripts.
- The `sysadm.git` subtest uses the env-only `POST_RECEIVE_SYSADM_DIR` seam in `bin/post-receive` to redirect the deployment target into a disposable temporary directory under the harness workspace. The production default remains `/etc/sysadm` unless a caller explicitly sets the env var.
- The `sysadm.git` path assumes the target directory already exists, so the test pre-creates that disposable temp target before running the hook. The assertions then prove stale files are removed, fixture content is moved into the contained target, `.git` is **not** moved into that target, and the run still continues through the shared `stagit` publishing tail under the temporary webroot `src/sysadm` directory.
- The `dotfiles.git` subtest uses an isolated harness HOME so the hook writes only to a temporary `$HOME/.local/bin`. It proves the current rename boundary from repository `.local/bin/ssg` to deployed `$HOME/.local/bin/ssg6`, replaces `rssg` in place, resets both deployed helper modes to `0700`, leaves no same-name `ssg` behind, and still flows through the shared publishing tail under the temporary webroot `src/dotfiles` directory.
- When either branch-specific subtest fails, TAP diagnostics deliberately name the temporary workspace, HOME, webroot, fake-command directory, fake `stagit` trace path, and contained deployment target/helper locations so a future executor can debug the failure without touching caller paths.
- Passing these Linux-hosted fake-helper tests does **not** prove production OpenBSD deployment. They intentionally stop at contained fixture behavior and leave real `which --`, real `stagit` / `ssg6` / `rssg` binaries, real filesystem layout, and real deployment side effects for separate host-level validation.

## Repository layout

- `bin/post-receive` — the extracted hook entrypoint. In M001 it remains the behavior-preserving copy from `sysadm` with only containment seams needed for safe characterization.
- `lib/PostReceive/TestHarness.pm` — the canonical isolated test harness module for this mirrored workspace.
- `t/lib/PostReceive/TestHarness.pm` — a compatibility shim so the existing characterization tests keep their current load path.
- `t/00-baseline.t` — a TAP baseline that checks the hook exists, is executable, and passes `perl -c` via `$^X` without normally running the hook.
- `t/01-harness-common.t` — an isolated runtime characterization that verifies repository metadata writes, temp-path containment, shared-asset copying, and staged output basics through a fake `stagit` shim.
- `t/02-shared-publishing.t` — the deterministic fake stagit shared publishing characterization that verifies output cleanup/recreation, the bare clone into `.git`, `git update-server-info`, `log.html` to `index.html`, shared asset copies, and the gzip eligibility/exclusion matrix under the isolated harness.
- `t/03-website-md.t` — the `website_md.git` branch-specific characterization that installs fake absolute-path `ssg6`/`rssg` helpers under an isolated HOME, keeps fake `stagit` on PATH for the shared publishing tail, and proves temp webroot containment plus website cleanup/RSS/gzip behavior.
- `t/04-deployment-branches.t` — the `sysadm.git` and `dotfiles.git` branch characterization that uses `POST_RECEIVE_SYSADM_DIR` plus an isolated HOME to keep deployment writes contained while still proving the shared `stagit` publishing tail.

## Prerequisites

Visible requirements from the current characterization work are:

- Perl v5.36+
- `prove`
- `git`
- Perl module `IPC::System::Simple`

A real `stagit` binary is only required for the separate live stagit smoke coverage outside this mirror. The mirrored TAP suite prepends its own fake `stagit` shim during runtime characterization so the in-worktree verification commands stay self-contained.

Real `ssg6` and `rssg` binaries are also unnecessary for the mirror suite. `t/03-website-md.t` installs deterministic fakes at `$HOME/.local/bin/ssg6` and `$HOME/.local/bin/rssg` under the harness HOME because the hook resolves those helpers by absolute path instead of by PATH lookup.

A real `/etc/sysadm` tree or a real caller `$HOME/.local/bin` is likewise unnecessary for the mirror suite. `t/04-deployment-branches.t` uses `POST_RECEIVE_SYSADM_DIR` plus a harness-local HOME so the deployment-oriented branches stay inside temporary containment.

## Verification

From the milestone worktree root, run the focused deployment-branches characterization when you are debugging only the `sysadm.git` or `dotfiles.git` branch paths:

```sh
prove -v post-receive-extracted/t/04-deployment-branches.t
```

From the milestone worktree root, run the focused website characterization when you are debugging only the `website_md.git` branch path:

```sh
prove -v post-receive-extracted/t/03-website-md.t
```

For the overall mirror suite, run either of these:

From the mirrored repository root:

```sh
prove -lr t
```

From the milestone worktree root:

```sh
prove -r post-receive-extracted/t
```

These commands keep verification inside the in-worktree mirror. `prove -v post-receive-extracted/t/04-deployment-branches.t` is the first branch-specific diagnostic for `sysadm.git` and `dotfiles.git` failures because it prints harness run details plus contained sysadm target, helper-bin, and fake `stagit` trace locations. `prove -v post-receive-extracted/t/03-website-md.t` remains the first branch-specific diagnostic for website failures because it prints harness run details plus fake `ssg6` / `rssg` / `stagit` trace locations. `prove -lr t` remains the supported repo-root full-suite check for fresh readers, while the worktree-root form is useful when the milestone runner invokes the mirror from one level up.

## Coverage and M002 handoff map

| Surface | Current evidence in this mirror | Boundary / what it does **not** prove |
|---|---|---|
| Generic shared publishing tail | `t/01-harness-common.t`, `t/02-shared-publishing.t`, plus the shared tail exercised again by `t/03-website-md.t` and `t/04-deployment-branches.t`; fake `stagit` proves cleanup/recreation, bare clone into `.git`, `git update-server-info`, `log.html` to `index.html`, shared asset copies, and gzip rules under temporary paths. | Does not prove real `stagit` HTML output, real binary behavior, or production host layout. |
| Live `stagit` smoke coverage outside this mirror | Stays with the original extracted-hook line of work that M001 treats as read-only input; use it when you need real-binary confirmation instead of the deterministic fake-`stagit` contract in this mirror. | Not duplicated or maintained here, and still not a full proof of production OpenBSD deployment side effects. |
| `website_md.git` branch | `t/03-website-md.t` uses fake absolute-path `ssg6` / `rssg` helpers plus fake `stagit` to prove contained website cleanup, deterministic RSS generation, asset reseeding, and the current narrow gzip behavior. | Does not prove real `ssg6` / `rssg` output, real website content rendering, or safe manual runs against host webroot paths. |
| `sysadm.git` branch | `t/04-deployment-branches.t` uses `POST_RECEIVE_SYSADM_DIR` and a pre-created disposable target under the harness workspace to prove stale-entry cleanup, fixture deployment into the contained target, `.git` exclusion, verbose-path reporting, and the shared publishing tail in `src/sysadm`. | Does not prove the real `/etc/sysadm` filesystem layout, ownership/permission expectations, service interactions, or other production deployment side effects. |
| `dotfiles.git` branch | `t/04-deployment-branches.t` uses an isolated HOME to prove helper replacement in temporary `$HOME/.local/bin`, the `.local/bin/ssg` to `$HOME/.local/bin/ssg6` rename boundary, `rssg` replacement, `0700` mode resets, caller-HOME isolation, and the shared publishing tail in `src/dotfiles`. | Does not prove real-user HOME behavior, shell/session integration, helper execution correctness after deployment, or host-specific dotfiles side effects. |
| Remaining OpenBSD-first gaps and where M002 should start | The hook still has OpenBSD-shaped assumptions: `which --` in dependency checks, absolute helper paths under `$HOME/.local/bin`, hard-coded production roots, and deployment logic interleaved with shared publishing. M002 should start by simplifying or isolating those assumptions behind seams that keep `t/03-website-md.t` and `t/04-deployment-branches.t` green as black-box regression coverage. | Until that simplification lands, mirror tests are characterization only: they are intentionally bounded and should not be described as proof of production OpenBSD compatibility. |

## Safety boundary

Do not run the hook normally against real repositories or deployment paths when characterizing it.

Even in this mirrored workspace, the extracted script still carries production-oriented behavior that can touch real host paths and deployment state when it runs outside the harness. In its normal mode it can:

- publish website content under `/var/www/htdocs/...`
- refresh the deployed `sysadm` tree under `/etc/sysadm`
- replace dotfiles helper binaries in `$HOME/.local/bin`
- regenerate `stagit` output for repository publishing

The harness tests are the safe execution surface. They add temporary bare repositories, an isolated HOME, an isolated `PATH`, seeded `stagit` assets, and path containment so the hook can be exercised without mutating the host.

## Compatibility posture

This project is OpenBSD-first because the hook assumes an operational layout and deployment style that matches the original environment.

A local Linux syntax check and harness run are still useful, but they only prove parsing and the contained characterization paths exercised by the tests. They do not prove full production compatibility for OpenBSD-only `which --` behavior, real helper binaries, real filesystem layout, process behavior, or deployment side effects.

## Why this mirror exists

The immediate goal is characterization, not cleanup. M001 captures the current behavior closely enough to build trustworthy tests first; only after that baseline exists should later milestones simplify or refactor the hook.
