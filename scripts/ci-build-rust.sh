#!/usr/bin/env bash
# 在 macOS 上编译 EasyTier 的 iOS 静态库（device slice）。
# 用法：./scripts/ci-build-rust.sh /path/to/EasyTier
set -euo pipefail

ET_DIR="${1:?第一个参数必须是 EasyTier 仓库路径}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: 这个脚本必须在 macOS 上跑（需要 Apple SDK）" >&2
  exit 1
fi

# Rust 的 iOS target 会调用 ___chkstk_darwin，但不会自动链 compiler-rt，需要手动指路
CLANG_BIN="$(xcrun --find clang)"
TOOLCHAIN_USR="${CLANG_BIN%/bin/clang}"
CLANG_RT_DIR="$(cd "${TOOLCHAIN_USR}/lib/clang" && cd "$(ls | sort -V | tail -1)/lib/darwin" && pwd)"
echo "==> libclang_rt: ${CLANG_RT_DIR}"

cd "${ET_DIR}"
rustup target add aarch64-apple-ios

echo "==> cargo build -p easytier-ios --release --target aarch64-apple-ios"
RUSTFLAGS="-C link-arg=-L${CLANG_RT_DIR} -C link-arg=-lclang_rt.ios" \
  cargo build -p easytier-ios --release --target aarch64-apple-ios

mkdir -p "${REPO_ROOT}/Frameworks"
cp target/aarch64-apple-ios/release/libeasytier_ios.a "${REPO_ROOT}/Frameworks/libeasytier_ios.a"

echo "==> 产物："
ls -lh "${REPO_ROOT}/Frameworks/libeasytier_ios.a"
lipo -info "${REPO_ROOT}/Frameworks/libeasytier_ios.a"
