.PHONY: test test-fast test-full

# Routine developer loop: build/artifact correctness plus essential smoke
# coverage. Use this for skill-content edits (commands-src/, _shared/).
test: test-fast

test-fast:
	./tests/run.sh --fast

# Everything: all 61 integration and regression tests. Required for changes to
# bin/, tests/, bin/targets/, or anything touching lifecycle, Git update,
# sync/bootstrap, target adapters, or xdh behavior.
test-full:
	./tests/run.sh --full
	bash ./tests/pr10-safety-regression.sh
	bash ./tests/pr15-regression.sh
