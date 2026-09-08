#!/usr/bin/env bash
# Non-interactive Mob Android setup for CI (and a fresh clone).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -z "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]]; then
  echo "ANDROID_HOME or ANDROID_SDK_ROOT must be set" >&2
  exit 1
fi

ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME"
export MIX_ENV="${MIX_ENV:-dev}"

if [[ ! -f mix.exs ]]; then
  echo "run from the battery_timer project root" >&2
  exit 1
fi

if [[ ! -f mob.exs ]]; then
  cat > mob.exs <<'EOF'
import Config

config :mob_dev,
  mob_dir: Path.join(File.cwd!(), "deps/mob"),
  elixir_lib:
    System.get_env("MOB_ELIXIR_LIB", :code.lib_dir(:elixir) |> to_string() |> Path.dirname()),
  static_nifs: [%{module: :battery, archs: [:android]}]

config :mob, :plugins, []

config :mob, :trusted_plugins, %{}
EOF
fi

mix local.hex --force
mix local.rebar --force
mix deps.get
mix mob.write_local_properties

echo "android/local.properties:"
cat android/local.properties
