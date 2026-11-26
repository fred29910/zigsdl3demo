#!/usr/bin/env sh
# Spec Kit RED/GREEN contract check for 002-upgrade-direct-deps.
# Asserts that build.zig.zon pins the exact target versions/hashes chosen in
# research.md. Expected to FAIL before the upgrades and PASS afterwards.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
ZON="$ROOT/build.zig.zon"
fail=0

has() { grep -Fq -- "$1" "$ZON"; }

check() {
    desc=$1
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$desc"
    else
        printf 'FAIL: %s\n' "$desc"
        fail=1
    fi
}

check "imgui 固定到 v1.93.0" has "imgui/archive/refs/tags/v1.93.0.tar.gz"
check "imgui 哈希精确锁定" has "N-V-__8AAEVjfgCU7hthaWtlDkNjFB4HE1XYqFl6UO7oqXwD"
check "jolt 固定到 v5.7.0" has "JoltPhysics/archive/refs/tags/v5.7.0.tar.gz"
check "jolt 哈希精确锁定" has "N-V-__8AAJgyLAL_wh69ee1vC-XK3z_zAims-XlafozU6HDG"
check "stb 固定到提交 6b5799b" has "stb/archive/6b5799bae8a1fe3792691ef4b72ae26434c3e799.tar.gz"
check "stb 哈希精确锁定" has "N-V-__8AAMNjVQBtQqFTqLXf4ajZ6COgMe1AG_STJHG4jkdj"
check "Zig 工具链仍为 0.17.1" has 'minimum_zig_version = "0.17.1"'

if grep -E '\.url = ' "$ZON" | grep -Eq 'refs/(heads|branches)/|#main|#master|latest'; then
    printf 'FAIL: 存在浮动版本引用\n'
    fail=1
else
    printf 'PASS: 无浮动版本引用\n'
fi

lazy_count=$(grep -c '\.lazy = true' "$ZON" || true)
if [ "$lazy_count" -eq 5 ]; then
    printf 'PASS: 5 项 lazy 依赖标记未变\n'
else
    printf 'FAIL: lazy 标记数量异常（期望 5，实际 %s）\n' "$lazy_count"
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    printf '\nRED: 目标版本尚未落地，禁止开始升级实现。\n'
    exit 1
fi

printf '\nGREEN: 全部目标版本与精确锁定规则满足。\n'
exit 0
