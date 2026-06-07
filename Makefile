.PHONY: hooks publish

# Install git hooks into this clone (run once per clone).
hooks:
	mkdir -p .git/hooks
	cp .githooks/pre-commit .git/hooks/pre-commit
	cp .githooks/pre-push   .git/hooks/pre-push
	chmod +x .git/hooks/pre-commit .git/hooks/pre-push
	@echo "hooks installed (pre-commit, pre-push) — run 'make hooks' in each clone"

# Publish this package to the registry in lex.toml (lex-hub).
# GitHub-independent: runs the full validate loop, then publishes using
# LEX_PUBLISH_TOKEN from the environment.
publish:
	@test -n "$$LEX_PUBLISH_TOKEN" || { echo "LEX_PUBLISH_TOKEN not set in environment"; exit 1; }
	lex ci
	lex pkg publish
