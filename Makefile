.PHONY: deploy

init:
	git worktree remove -f /tmp/rustcbook
	git worktree add -f /tmp/rustcbook gh-pages

deploy: init
	@echo "====> deploying to github"
	mdbook build
	rm -rf /tmp/rustcbook/*
	cp -rp book/* /tmp/rustcbook/
	cd /tmp/book && \
		git add -A && \
		git commit -m "deployed on $(shell date) by ${USER}" && \
		git push origin gh-pages