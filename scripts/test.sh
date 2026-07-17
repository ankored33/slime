#!/usr/bin/env bash
# 全テストを実行する。どれかが落ちたら非ゼロで終了する。
set -eu
cd "$(dirname "$0")/.."
# class_name のグローバルキャッシュが古いとテストがパースエラーで誤動作するため、先に再インポートする。
godot --headless --path godot --import >/dev/null
godot --headless --path godot -s res://tests/run_tests.gd
godot --headless --path godot -s res://tests/run_flow_tests.gd
