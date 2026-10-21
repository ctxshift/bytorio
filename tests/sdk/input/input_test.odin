package input_test

import abi "../../../runtime/odin/abi"
import "core:testing"

@(test)
legacy_and_versioned_replay :: proc(t: ^testing.T) {
    legacy, legacy_ok := abi.parse_input("31")
    testing.expect(t, legacy_ok)
    testing.expect_value(t, legacy.buttons, 31)
    testing.expect(t, !legacy.pointer)
    testing.expect_value(t, legacy.x, 0)
    input, ok := abi.parse_input("v2:4294967295:1:17.25:18.5")
    testing.expect(t, ok)
    testing.expect_value(t, input.buttons, 0xffffffff)
    testing.expect(t, input.pointer)
    testing.expect_value(t, input.x, 17.25)
    testing.expect_value(t, input.y, 18.5)
    hover, hover_ok := abi.parse_input("v2:262144:0:80.5:60.75")
    testing.expect(t, hover_ok && !hover.pointer)
    testing.expect_value(t, hover.x, 80.5)
}

@(test)
reject_invalid_replay :: proc(t: ^testing.T) {
    invalid := []string {
        "",
        "-1",
        "4294967296",
        "v1:0:0:1:2",
        "v2:0:2:1:2",
        "v2:0:0:NaN:2",
        "v2:0:0:1:Inf",
        "v2:0:0:1",
        "v2:0:0:1:2:3",
        "v2:word:0:1:2",
    }
    for token in invalid {
        _, ok := abi.parse_input(token)
        testing.expect(t, !ok, token)
    }
}
