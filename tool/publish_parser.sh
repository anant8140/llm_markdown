#!/bin/sh
# Publishes packages/llm_markdown_parser.
#
# It is published from a copy outside this repository: the .pubignore of
# llm_markdown, one folder up, leaves packages/ out of llm_markdown and
# would hide every file of the parser too.
#
#   tool/publish_parser.sh --dry-run
#   tool/publish_parser.sh
set -e
cd "$(dirname "$0")/.."
copy="$(mktemp -d)/llm_markdown_parser"
cp -R packages/llm_markdown_parser "$copy"
rm -rf "$copy/.dart_tool" "$copy/pubspec.lock"
cd "$copy"
dart pub get
dart pub publish "$@"
rm -rf "$(dirname "$copy")"
