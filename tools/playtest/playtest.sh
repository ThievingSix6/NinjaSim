#!/bin/sh
# Headless playtest: builds the place with Rojo, then runs server + one client
# inside Lune with an emulated engine and drives a full gameplay scenario.
# SCENARIO=uishots dumps the HUD and every menu to JSON instead (UISHOTS_DIR, default
# /tmp/claude-0/uishots); render them with tools/uipreview/shoot.mjs.
# NINJA_MESHES=1 pretends the asset pack (and icon atlas) was imported.
# Requires rojo and lune (https://github.com/lune-org/lune) on PATH, or LUNE=/path/to/lune.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
rojo build "$ROOT/default.project.json" -o "$ROOT/NinjaSim.rbxl" >/dev/null
cd "$HERE"
${LUNE:-lune} run run.luau "$ROOT/NinjaSim.rbxl"
