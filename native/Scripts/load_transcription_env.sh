#!/usr/bin/env bash
#
# load_transcription_env.sh
#
# development helper that loads transcription service api keys from a local
# config file. hook this script into the run-scheme pre-action so xcode picks up
# the env vars without hard-coding them inside the project.
#
# expected config file (not committed):
#   ${HOME}/.config/ai-and-i/env
# containing lines such as:
#   export GEMINI_API_KEY="..."
#   export DEEPGRAM_API_KEY="..."
#   export ASSEMBLYAI_API_KEY="..."
#
# optionally set AI_AND_I_ENV_PATH to point somewhere else.

set -euo pipefail

CONFIG_PATH="${AI_AND_I_ENV_PATH:-$HOME/.config/ai-and-i/env}"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "⚠️  ai&i env file not found at $CONFIG_PATH" >&2
  echo "    create the file with export statements for transcription keys." >&2
  exit 0
fi

# shellcheck disable=SC1090
source "$CONFIG_PATH"

missing=0
for key in GEMINI_API_KEY DEEPGRAM_API_KEY ASSEMBLYAI_API_KEY; do
  if [[ -z "${!key:-}" ]]; then
    echo "⚠️  $key missing in $CONFIG_PATH" >&2
    missing=1
  fi
  export "$key"
done

if [[ $missing -eq 0 ]]; then
  echo "✅ transcription env loaded from $CONFIG_PATH"
else
  echo "⚠️  transcription env loaded with warnings" >&2
fi
