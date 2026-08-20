.PHONY: test test-fast test-full

# Routine developer loop: build/artifact correctness plus essential smoke
# coverage. Use this for skill-content edits (commands-src/, _shared/).
test: test-fast

test-fast:
	./tests/run.sh --fast

# Everything: all integration and regression tests. Required for changes to
# bin/, tests/, bin/targets/, or anything touching lifecycle, Git update,
# sync/bootstrap, target adapters, or xdh behavior.
test-full:
	./tests/run.sh --full
	bash ./tests/plan-machine-regression.sh
	bash ./tests/plan-content-regression.sh
	bash ./tests/survey-regression.sh
	bash ./tests/survey-cache-regression.sh
	bash ./tests/pr10-safety-regression.sh
	bash ./tests/pr15-regression.sh
