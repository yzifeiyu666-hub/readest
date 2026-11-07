#!/usr/bin/env bash
# Cross-build the Windows x64 self-hosted desktop app on Linux.
# Uses cargo-xwin (MSVC/WinSDK downloaded by xwin). This is not the
# official GitHub Actions path, which runs on windows-latest. Do not
# describe the result as an MSVC 14.44 link.
set -euo pipefail

NODE_BIN="${NODE_BIN:-/usr/local/bin}"
CARGO_BIN="${CARGO_BIN:-/usr/local/cargo/bin}"
export PATH="${NODE_BIN}:${CARGO_BIN}:${PATH}"

NODE_VERSION=24.22.2
PNPM_VERSION=11.1.1
RUST_VERSION=1.99.1
XWIN_VERSION=0.23.1
TARGET=x86_64-pc-windows-msvc

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"

node_actual=$(node -v)
[[ "$node_actual" == "v${NODE_VERSION}" ]] || {
  echo "node is $node_actual; expected v${NODE_VERSION}" >&2
  exit 1
}
pnpm_actual=$(pnpm -v)
[[ "$pnpm_actual" == "$PNPM_VERSION" ]] || {
  echo "pnpm is $pnpm_actual; expected $PNPM_VERSION" >&2
  exit 1
}
rustc_actual=$(rustc --version)
[[ "$rustc_actual" == rustc\ ${RUST_VERSION}\ * ]] || {
  echo "rustc is $rustc_actual; expected ${RUST_VERSION}" >&2
  exit 1
}
# Add the target to whichever toolchain `rustc` resolves (stable), not a
# separately named 1.99.1 toolchain. Tauri invokes `rustc` from PATH.
rustup target add "$TARGET"
xwin_actual=$(cargo-xwin --version)
[[ "$xwin_actual" == "cargo-xwin ${XWIN_VERSION}" ]] || {
  echo "cargo-xwin is '$xwin_actual'; expected cargo-xwin ${XWIN_VERSION}" >&2
  exit 1
}

export NEXT_PUBLIC_SELF_HOSTED=true
export NEXT_PUBLIC_APP_PLATFORM=tauri
# Drop a previous export. Next will otherwise reuse a bundle that baked
# operator quota values from another shell.
rm -rf apps/readest-app/.next apps/readest-app/out
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=6144}"

pnpm install --frozen-lockfile
pnpm --filter @readest/readest-app setup-vendors

# Invoke the wry CLI directly. `pnpm tauri` on Linux switches the build to
# the CEF runtime, which is the Linux desktop and not a Windows exe.
cd apps/readest-app
node ./node_modules/@tauri-apps/cli/tauri.js build \
  --config src-tauri/tauri.selfhosted.windows.json \
  --runner cargo-xwin \
  --target "$TARGET" \
  --bundles nsis

echo "exe: ${repo_root}/target/${TARGET}/release/readest-selfhosted.exe"
echo "nsis: ${repo_root}/target/${TARGET}/release/bundle/nsis/"
