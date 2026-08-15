.PHONY: test

test:
	./tests/run.sh
	bash ./tests/pr10-safety-regression.sh
	bash ./tests/pr15-regression.sh
