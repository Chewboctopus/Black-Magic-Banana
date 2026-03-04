SHELL := /bin/bash

.PHONY: savepoint deploy rollback

savepoint:
	./tools/savepoint.sh

deploy:
	./tools/deploy.sh

rollback:
	./tools/rollback.sh
