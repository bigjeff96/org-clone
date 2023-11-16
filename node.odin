package orgclone

import "core:mem"
import "core:mem/virtual"
import "core:slice"
import "core:strings"

Node :: struct($T: typeid) {
    value:    ^T,
    next:     ^Node(T),
    previous: ^Node(T),
}

Node_list :: struct($T: typeid) {
    first: ^Node(T),
    last:  ^Node(T),
    count: int,
}

Header_value :: struct {
    text:              strings.Builder,
    lines:             [dynamic]Line,
    indentation_level: int,
}

Node_general :: struct($T: typeid) {
    using value:      T,
    next:             ^Node_general(T),
    previous:         ^Node_general(T),
    parent:           ^Node_general(T),
    using child_list: struct {
        first: ^Node_general(T),
        last:  ^Node_general(T),
        count: int,
    },
}

Header_test :: Node_general(Header_value)

node_append_list :: proc(node: ^Node_general, element: ^Node_general) {
    assert(node != nil && element != nil)
    using node
    last.next = element
    element.previous = last
    last = element
    count += 1
}
