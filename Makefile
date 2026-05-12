.PHONY: check syntax lint tidy-check test no-backups require-perlcritic require-perltidy

check: syntax lint tidy-check no-backups test

syntax:
	perl -c bin/post-receive

require-perlcritic:
	@command -v perlcritic >/dev/null 2>&1 || { echo "Missing developer tool: perlcritic (Perl::Critic). Install Perl::Critic before running make lint/check." >&2; exit 127; }

lint: require-perlcritic
	perlcritic bin lib t

require-perltidy:
	@command -v perltidy >/dev/null 2>&1 || { echo "Missing developer tool: perltidy. Install perltidy before running make tidy-check/check." >&2; exit 127; }

tidy-check: require-perltidy
	@status=0; \
	for file in bin/post-receive $$(find lib t -type f \( -name '*.pm' -o -name '*.pl' -o -name '*.t' \) | sort); do \
		echo "perltidy --assert-tidy $$file"; \
		perltidy --assert-tidy -st -se "$$file" >/dev/null || status=1; \
	done; \
	exit $$status

no-backups:
	@backups=$$(find bin lib t -name '*.bak' -print); \
	if [ -n "$$backups" ]; then \
		echo "Remove generated backup files before committing:" >&2; \
		printf '%s\n' "$$backups" >&2; \
		exit 1; \
	fi

test:
	prove -lr t
