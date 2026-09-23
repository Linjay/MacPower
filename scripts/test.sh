#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
SWIFT_BIN=$(xcrun --find swiftc)
TESTING_PLUGIN="${SWIFT_BIN:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
# CLT 6.4 includes Swift Testing but its default build engine misses the nested macro path.
if [[ -f "$TESTING_PLUGIN" ]]; then
    swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN"
else
    swift test --disable-xctest
fi
