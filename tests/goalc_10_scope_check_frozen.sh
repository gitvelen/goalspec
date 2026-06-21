#!/usr/bin/env bash
# GOALC #10: after freeze, Subagent modifying contract.yaml / project/** / history/**
#            or out-of-scope paths must fail scope-check.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fresh_initialized_repo goalc-10
"$REPO_GS" new-goal "test" >/dev/null
make_minimal_goal_md "$REPO/.goalspec/active/goal.md"
approve_intake_and_goal
"$REPO_GS" compile >/dev/null
make_minimal_contract "$REPO/.goalspec/active/contract.yaml"
tmp="$TESTS_TMP_ROOT/p10"; mkdir -p "$tmp"
cat > "$tmp/c.yaml" <<'YML'
kind: contract
result: pass
blocking_questions: []
notes: ok
YML
"$REPO_GS" review apply "$tmp/c.yaml" >/dev/null
"$REPO_GS" approve contract >/dev/null
"$REPO_GS" freeze >/dev/null
# Commit baseline so dirty is measured against HEAD post-freeze.
git add -A && git commit -q -m frozen-baseline
base_head="$(git rev-parse HEAD)"
BASE_HEAD="$base_head" yq e -i '.git.base_revision = strenv(BASE_HEAD)' "$REPO/.goalspec/active/state.yaml"

# A) collaboration guide edits are framework metadata, not business scope.
echo "collaboration note" >> "$REPO/AGENTS.md"
echo "collaboration note" >> "$REPO/CLAUDE.md"
if "$REPO_GS" scope-check >/dev/null 2>&1; then
  ok "scope-check ignores collaboration guide edits as business scope"
else
  bad "scope-check treated collaboration guides as out-of-scope business files"
fi
git checkout -- AGENTS.md CLAUDE.md

# B) invoking this goalspec from another repo must still inspect this project.
CALLER="$TESTS_TMP_ROOT/caller-repo"
mkdir -p "$CALLER/billing"
( cd "$CALLER" && git init -q && git config user.email t@t && git config user.name t && touch base && git add -A && git commit -q -m base && echo x > billing/x.txt )
if ( cd "$CALLER" && "$REPO_GS" scope-check >/dev/null 2>&1 ); then
  ok "scope-check uses invoked project root, not caller cwd repo"
else
  bad "scope-check was polluted by caller cwd repo"
fi

# C) modify contract.yaml content (hash changes)
yq e -i '.criteria[0].statement = "TAMPERED"' "$REPO/.goalspec/active/contract.yaml"
if "$REPO_GS" scope-check >/dev/null 2>&1; then
  bad "scope-check did not catch contract.yaml content tampering"
else
  ok "scope-check caught contract.yaml content tampering"
fi
git checkout -- .goalspec/active/contract.yaml

# D) modify project/memory.yaml
echo x >> "$REPO/.goalspec/project/memory.yaml"
if "$REPO_GS" scope-check >/dev/null 2>&1; then
  bad "scope-check did not catch project/memory.yaml modification"
else
  ok "scope-check caught project/memory.yaml modification"
fi
git checkout -- .goalspec/project/memory.yaml

# E) add file under history/**
mkdir -p "$REPO/.goalspec/history"; echo x > "$REPO/.goalspec/history/hack.yaml"
if "$REPO_GS" scope-check >/dev/null 2>&1; then
  bad "scope-check did not catch history/** write"
else
  ok "scope-check caught history/** write"
fi
/bin/rm -rf "$REPO/.goalspec/history/hack.yaml"

# F) edit file outside contract allowed_paths (billing is not under src/**)
mkdir -p "$REPO/billing"; echo x > "$REPO/billing/x.txt"
if "$REPO_GS" scope-check >/dev/null 2>&1; then
  bad "scope-check did not catch out-of-scope path write"
else
  ok "scope-check caught out-of-scope path write"
fi
/bin/rm -rf "$REPO/billing"

# G) Subagent direct edit of verdict.yaml (subagent role)
echo x > "$REPO/.goalspec/active/verdict.yaml"
if "$REPO_GS" scope-check >/dev/null 2>&1; then
  bad "scope-check did not catch Subagent verdict.yaml write"
else
  ok "scope-check caught Subagent verdict.yaml write"
fi
/bin/rm -f "$REPO/.goalspec/active/verdict.yaml"

[ "$TESTS_FAIL" -eq 0 ]
