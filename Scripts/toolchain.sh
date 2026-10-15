# Prefer the user's active toolchain; fall back to already installed Command Line
# Tools if a newly selected Xcode has not completed first-launch configuration.
if ! xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 && [[ -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
