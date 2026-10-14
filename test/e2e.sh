#!/usr/bin/env bash
# Runs the real Claude Code CLI against test/mock-server.mjs with settings written by ccp,
# in a throwaway HOME, and prints which model ID each kind of request used.
#
#   CLAUDE_BIN=/path/to/claude test/e2e.sh                 # all presets
#   CLAUDE_BIN=/path/to/claude test/e2e.sh deepseek kimi   # some presets
#
# Needs: node, curl, python3, and a Claude Code install. Uses port 8788.
# WebFetch fetches https://example.com once per preset (that is what triggers the background model).
set -u
ONLY="$*"
HERE="$(cd "$(dirname "$0")" && pwd)"
CCP="$HERE/../ccp"
CLAUDE="${CLAUDE_BIN:-claude}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ccp-e2e.XXXXXX")"
trap 'pkill -f "$HERE/mock-server.mjs" 2>/dev/null; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home/.claude" "$WORK/proj"
export LOG="$WORK/req.jsonl"
# Skip onboarding and trust prompts in the throwaway HOME.
printf '{"hasCompletedOnboarding":true,"projects":{"%s":{"hasTrustDialogAccepted":true}}}' "$WORK/proj" > "$WORK/home/.claude.json"

startmock() { # $1 accepted models (comma list), $2 optional VAR=value
  pkill -f "$HERE/mock-server.mjs" 2>/dev/null; sleep 0.3
  ( env MOCK_MODELS="$1" ${2:+"$2"} node "$HERE/mock-server.mjs" > "$WORK/mock.out" 2>&1 & ); sleep 0.8
  rm -f "$LOG"
}
cc() { # only PATH and HOME: every provider setting has to come from settings.json
  ( cd "$WORK/proj" && env -i PATH="$PATH" HOME="$WORK/home" TERM=dumb CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 "$CLAUDE" "$@" < /dev/null > "$WORK/cc.out" 2>&1 )
}
seen() { python3 - "$LOG" <<'EOF'
import json, os, sys
rows = [json.loads(l) for l in open(sys.argv[1])] if os.path.exists(sys.argv[1]) else []
models = sorted(set(r['model'] for r in rows))
auth = sorted(set(('Bearer' if r['bearer'] == 'ok' else '') + ('x-api-key' if r['xapikey'] == 'ok' else '') for r in rows))
print(' '.join(models) or '(no request)', '| auth:', ' '.join(auth))
EOF
}

run() { # $1 preset ("custom" = no preset), $2 models the mock accepts, rest = extra ccp args
  local p=$1 acc=$2; shift 2
  rm -f "$WORK/home/.claude/settings.json" "$WORK/home/.claude/settings.json.ccp-backup"
  local name=(); [ "$p" != custom ] && name=("$p")
  CCP_API_KEY=test-key-123 HOME="$WORK/home" "$CCP" use ${name[@]+"${name[@]}"} --base-url http://127.0.0.1:8788 "$@" > "$WORK/use.out" 2>&1 \
    || { echo "== $p: ccp use failed"; cat "$WORK/use.out"; return; }
  echo "== $p"
  startmock "$acc" "MOCK_TOOL=WebFetch:{\"url\":\"https://example.com/?r=$RANDOM\",\"prompt\":\"summarize\"}"
  cc -p "fetch it" --permission-mode default --allowedTools WebFetch; echo "  main + WebFetch summary:  $(seen)"
  startmock "$acc" MOCK_SUBAGENT=1
  cc -p "go" --permission-mode default --allowedTools Agent;        echo "  main + subagent:          $(seen)"
  startmock "$acc" MOCK_SUBAGENT=1
  cc -p "go";                                                        echo "  auto-mode classifier:     $(seen)"
  for a in opus sonnet haiku fable; do
    startmock "$acc"; cc -p --model "$a" "hi"; printf '  --model %-17s %s\n' "$a:" "$(seen)"
  done
}

declare -a ALL=(
  "custom m-main,m-opus,m-sonnet,m-haiku,m-fable,m-sub --main m-main --opus m-opus --sonnet m-sonnet --haiku m-haiku --fable m-fable --subagent m-sub"
  "deepseek deepseek-flash"
  "kimi kimi-k3"
  "zai glm-5.3-flash"
  "minimax MiniMax-M3.1-Flash-Preview"
  "qwen qwen3.7-max,qwen3.6-flash"
  "qwen-coding qwen3.7-plus"
  "openrouter ~anthropic/claude-opus-latest,~anthropic/claude-sonnet-latest,~anthropic/claude-haiku-latest,~anthropic/claude-fable-latest"
  "litellm my-model,my-small --model my-model --small-model my-small"
  "standardcompute standardcompute"
)
"$CLAUDE" --version
for row in "${ALL[@]}"; do
  set -- $row
  if [ -z "$ONLY" ] || [[ " $ONLY " == *" $1 "* ]]; then run "$@"; fi
done
