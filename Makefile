.PHONY: test test-fast test-full test-timeout

FAST_TIMEOUT_SECONDS ?= 300
FULL_TIMEOUT_SECONDS ?= 3600

test: test-fast

test-fast:
	SKILL_X_SUITE_TIMEOUT_SECONDS="$${SKILL_X_SUITE_TIMEOUT_SECONDS:-$(FAST_TIMEOUT_SECONDS)}" bash ./tests/run-suite.sh fast bash ./tests/fast.sh

test-full:
	SKILL_X_SUITE_TIMEOUT_SECONDS="$${SKILL_X_SUITE_TIMEOUT_SECONDS:-$(FULL_TIMEOUT_SECONDS)}" bash ./tests/run-suite.sh core ./tests/run.sh
	SKILL_X_SUITE_TIMEOUT_SECONDS="$${SKILL_X_SUITE_TIMEOUT_SECONDS:-$(FULL_TIMEOUT_SECONDS)}" bash ./tests/run-suite.sh safety bash ./tests/pr10-safety-regression.sh
	SKILL_X_SUITE_TIMEOUT_SECONDS="$${SKILL_X_SUITE_TIMEOUT_SECONDS:-$(FULL_TIMEOUT_SECONDS)}" bash ./tests/run-suite.sh targets bash ./tests/pr15-regression.sh

test-timeout:
	@output=$$(mktemp "$${TMPDIR:-/tmp}/skill-x-timeout-check.XXXXXX"); \
	if SKILL_X_SUITE_TIMEOUT_SECONDS=1 bash ./tests/run-suite.sh timeout-check bash -c 'sleep 5' >"$$output" 2>&1; then \
		cat "$$output"; \
		rm -f "$$output"; \
		echo 'timeout check unexpectedly passed' >&2; \
		exit 1; \
	fi; \
	cat "$$output"; \
	grep -q 'TIMEOUT' "$$output"; \
	rm -f "$$output"
