#!/usr/bin/env bash
# Test evidence for engineering-audit-haljordan-muaddib scripts. Run: tests/run_tests.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; S="$here/.."
tmp=$(mktemp -d); pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS  $1"; }; bad(){ fail=$((fail+1)); echo "FAIL  $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
C="python3 $S/scripts/check_citations.py"

# fixture repo
r="$tmp/repo"; mkdir -p "$r/src" "$r/docs" "$r/scripts"; cd "$r"
printf 'const a = 1;\nexport function findByEmail() {}\nconst c = 3;\n' > src/short.js          # 3 lines
printf 'FROM node:20\nWORKDIR /app\n' > Dockerfile                                              # 2 lines
printf 'one\ntwo\n' > "docs/has spaces.md"                                                       # 2 lines
printf '{"name":"x","scripts":{"deploy":"API_TOKEN=abc123 railway up","test":"jest"}}' > package.json
echo 'SECRET=real' > .env; echo 'echo run' > scripts/run.sh
git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init

run(){ printf '%s\n' "$1" > "$tmp/r.md"; $C "$tmp/r.md" --root "$r" > "$tmp/out" 2>&1; echo $?; }

check "range end beyond file (short.js:2-999) is rejected"      "[[ \$(run 'see \`src/short.js:2-999\`') -eq 1 ]] && grep -q 'BAD RANGE' $tmp/out"
check "inverted range (short.js:3-1) is rejected"               "[[ \$(run 'see \`src/short.js:3-1\`') -eq 1 ]] && grep -q 'BAD RANGE' $tmp/out"
check "valid range (short.js:1-3) passes"                       "[[ \$(run 'see \`src/short.js:1-3\`') -eq 0 ]]"
check "extensionless file, bad line (Dockerfile:999) rejected"  "[[ \$(run 'see \`Dockerfile:999\`') -eq 1 ]] && grep -q 'BAD LINE' $tmp/out"
check "extensionless bare token (Dockerfile:999) also caught"   "[[ \$(run 'see Dockerfile:999 here') -eq 1 ]] && grep -q 'BAD LINE' $tmp/out"
check "extensionless file, good line (Dockerfile:2) passes"     "[[ \$(run 'see \`Dockerfile:2\`') -eq 0 ]]"
check "path with spaces resolves (docs/has spaces.md:1)"        "[[ \$(run 'see \`docs/has spaces.md:1\`') -eq 0 ]] && grep -q 'checked 1 citations' $tmp/out"
check "missing file reported"                                   "[[ \$(run 'see \`src/missing.ts:1\`') -eq 1 ]] && grep -q 'MISSING FILE' $tmp/out"
check "URLs, IP:port, localhost and clock times are ignored"    "[[ \$(run 'https://example.com:443/x 127.0.0.1:8080 localhost:3000 at 13:16 today') -eq 2 ]] && grep -q 'checked 0 citations' $tmp/out"
check "zero citations -> exit 2 and explicit message"           "[[ \$(run 'no evidence here') -eq 2 ]] && grep -q 'no citations found' $tmp/out"
check "symbol near the cited line passes"                       "[[ \$(run 'see \`src/short.js:2\` (\`findByEmail\`)') -eq 0 ]]"
check "symbol NOT near the cited line is a problem"             "[[ \$(run 'see \`src/short.js:2\` (\`deleteUser\`)') -eq 1 ]] && grep -q 'SYMBOL NOT NEAR' $tmp/out"
check "--lenient-symbols downgrades symbol mismatch to warning" "python3 $S/scripts/check_citations.py $tmp/r.md --root $r --lenient-symbols >$tmp/out 2>&1; [[ \$? -eq 0 ]] && grep -q 'WARN SYMBOL' $tmp/out"
check "malformed backticked citation is reported as unparsed"   "[[ \$(run 'see \`src/short.js: 2\` and \`src/short.js:2\`') -eq 0 ]] && grep -q 'WARN UNPARSED' $tmp/out"
check "same citation twice is checked once"                     "[[ \$(run 'a \`src/short.js:1\` b \`src/short.js:1\`') -eq 0 ]] && grep -q 'checked 1 citations' $tmp/out"

# inventory: names only by default, redaction with --commands, never .env content
bash "$S/scripts/inventory.sh" "$r" > "$tmp/inv" 2>&1
check "inventory default: script names only, no command values"  "grep -q '^deploy$' $tmp/inv && ! grep -q 'railway up' $tmp/inv"
check "inventory default: token never printed"                   "! grep -q 'abc123' $tmp/inv && ! grep -q 'SECRET=real' $tmp/inv"
bash "$S/scripts/inventory.sh" "$r" --commands > "$tmp/inv2" 2>&1
check "inventory --commands: command shown with secret redacted" "grep -q 'API_TOKEN=<redacted> railway up' $tmp/inv2 && ! grep -q 'abc123' $tmp/inv2"
check "inventory lists env file names only"                      "grep -q '^\.env$' $tmp/inv"

cd "$here"; echo "----"; echo "passed $pass, failed $fail"; rm -rf "$tmp"; [[ $fail -eq 0 ]]
