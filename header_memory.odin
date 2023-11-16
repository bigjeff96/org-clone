package orgclone

import "core:mem"
import "core:mem/virtual"
import "core:slice"
import "core:strings"

Header_memory_manager :: struct {
    raw_headers: [dynamic]Header,
    free_list:   ^Node(Header),
    allocator:   mem.Allocator,
}

init_header_memory_manager :: proc(using h: ^Header_memory_manager) {
    arena: virtual.Arena
    err := virtual.arena_init_growing(&arena)
    if err != .None do panic("failed in making virtual arena allocator")
    arena_allocator := virtual.arena_allocator(&arena)
    h.allocator = arena_allocator

    raw_headers = make([dynamic]Header, h.allocator)
    append(&raw_headers, Header{})
    free_list = new(Node(Header))
    free_list.value = &raw_headers[0]
    free_list.next = nil
}

@(require_results)
make_header :: proc(using h: ^Header_memory_manager) -> ^Header {
    result := free_list.value

    if free_list.next != nil {
        free(free_list)
        free_list = free_list.next
    } else {
        append(&raw_headers, Header{})
        using header := slice.last(raw_headers[:])
        builder = strings.builder_make()
        lines = make([dynamic]Line)
        children_headers = make([dynamic]^Header)
        free_list.value = &raw_headers[len(raw_headers) - 1]
    }
    return result
}

delete_current_header :: proc(using editor: ^Editor) {
    using header := headers[header_id]
    using header_memory_manager

    //remove this header from the children_headers list of its parent
    if parent_header != nil && len(parent_header.children_headers) > 0 {
        child_id := 0
        for child_header, id in parent_header.children_headers[:] do if child_header == header {
            child_id = id
            break
        }
        unordered_remove(&parent_header.children_headers, child_id)
    }

    clear(&builder.buf)
    clear(&lines)
    clear(&children_headers)
    work_state = .none
    toggle_state = .none
    parent_header = nil
    indentation_level = 0

    new_free_list := new(Node(Header))
    new_free_list.value = header
    new_free_list.next = free_list
    free_list = new_free_list

    ordered_remove(&headers, header_id)
    header_id = min(header_id, len(headers) - 1)
}
