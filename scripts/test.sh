#!/usr/bin/env bash
# 全テストを実行する。どれかが落ちたら非ゼロで終了する。
set -eu
cd "$(dirname "$0")/.."
godot --headless --path godot -s res://tests/run_tests.gd
godot --headless --path godot -s res://tests/run_flow_tests.gd
