#!/usr/bin/env bash
# Non-interactive Mob Android setup for CI (and a fresh clone).
# Writes gitignored mob.exs / android/local.properties, fetches Hex deps,
# downloads arm64 + x86_64 OTP runtimes into ~/.mob/cache.
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

ensure_otp() {
  local abi="$1"
  mix eval "
    case MobDev.OtpDownloader.ensure_android(\"${abi}\") do
      {:ok, path} -> IO.write(path)
      other -> Mix.raise(\"OTP ${abi}: \" <> inspect(other))
    end
  "
}

otp_arm64="$(ensure_otp arm64-v8a)"
otp_arm32="$(ensure_otp armeabi-v7a)"
otp_x86="$(ensure_otp x86_64)"
mob_dir="$root/deps/mob"

mkdir -p android
cat > android/local.properties <<EOF
sdk.dir=${ANDROID_HOME}
mob.otp_release=${otp_arm64}
mob.otp_release_arm32=${otp_arm32}
mob.otp_release_x86_64=${otp_x86}
mob.mob_dir=${mob_dir}
EOF

echo "android/local.properties:"
cat android/local.properties
