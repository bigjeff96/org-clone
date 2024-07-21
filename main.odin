package orgclone

import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:runtime"
import "core:slice"
import "core:strings"
import "core:testing"
import mu_rl "microui_raylib"
import mu "vendor:microui"
import rl "vendor:raylib"
import "vendor:stb/src"

TICK_DURATION :: 15
INDENTATION_AMOUNT :: 15
HEADERS_ONE_LINE :: true
FONT_SIZE :: 20

TESTING :: true

Line :: struct {
    start: int,
    end:   int,
}

Editor :: struct {
    header_id:             int,
    cursor_position:       int,
    prev_key:              rl.KeyboardKey,
    tick:                  int,
    font:                  rl.Font,
    text_measure:          rl.Vector2,
    font_size:             int,
    headers:               [dynamic]^Header,
    header_memory_manager: Header_memory_manager,
}

//TODO: each header should know its position in the header list
// maybe in the editor struct, we have a hash map of header_id -> ^header
// at the end of each event loop, we update the hash map if needed
Header :: struct {
    work_state:        enum {
        none,
        todo,
        done,
        waiting,
    },
    toggle_state:      enum {
        none,
        hidden,
        just_header,
        subheaders,
        sub_subheaders,
    },
    builder:           strings.Builder,
    lines:             [dynamic]Line,
    parent_header:     ^Header,
    children_headers:  [dynamic]^Header,
    indentation_level: int,
}

init_editor :: proc(using editor: ^Editor, font_size_to_use: int) -> mem.Allocator_Error {
    font = rl.LoadFont("FiraCode-Regular.ttf")
    font_size = font_size_to_use
    text_measure = rl.MeasureTextEx(font, "t", auto_cast font_size, 0)
    tick = TICK_DURATION
    init_header_memory_manager(&header_memory_manager)

    headers = make([dynamic]^Header)
    append(&headers, make_header(&header_memory_manager))
    return .None
}

main :: proc() {
    using rl
    SetWindowState({.MSAA_4X_HINT, .VSYNC_HINT, .WINDOW_RESIZABLE})
    SetTargetFPS(60)
    InitWindow(500, 500, "org-clone")
    defer CloseWindow()

    ctx := mu_rl.raylib_cxt()
    editor: Editor
    err := init_editor(&editor, FONT_SIZE)
    if err != .None do panic("error in editor allocation")
    using editor

    when TESTING {
        for _ in 0 ..< 10 {
            append(&headers, make_header(&header_memory_manager))
        }
        for i in 0 ..< len(headers) {
            using header := headers[i]
            strings.write_string(&header.builder, fmt.tprintf("Header %v\n", i))
        }
    }

    for !WindowShouldClose() {
        defer free_all(context.temp_allocator)

        mu_rl.mu_input(ctx)
        BeginDrawing()
        defer EndDrawing()
        defer mu_rl.render(ctx)
        ClearBackground(BLACK)
        mu.begin(ctx)
        defer mu.end(ctx)

        key := rl.GetKeyPressed()
        {     // Update key and reset tick
            prev_key = key if key != .KEY_NULL else prev_key
            if key != .KEY_NULL do tick = TICK_DURATION
        }

        if key != .KEY_NULL do execute_command(&editor, key)
        else {
            if IsKeyDown(prev_key) {
                if tick > 0 do tick -= 1
                else do execute_command(&editor, prev_key)
            }
        }

        {     // determine lines in builder
            //NOTE: Just doing it for header 1, will need to make it general
            //(only do it for headers that just changed, or simply for the header_id)
            using header := headers[header_id]
            clear(&lines)
            for char, id in strings.to_string(builder) {
                if char == '\n' || id == strings.builder_len(builder) - 1 {
                    if len(lines) == 0 {
                        //NOTE: First line doesn't need to end with a '\n'
                        append(&lines, Line{0, id})
                    } else {
                        line: Line
                        line.start = slice.last(lines[:]).end + 1
                        line.end = id
                        append(&lines, line)
                    }
                }
            }
        }

        cursor_coords: [2]int
        cursor_x_offset: int
        {
            using header := headers[header_id]
            current_line_id := get_visual_cursor_line_id(editor)
            cursor_x_offset = indentation_level * INDENTATION_AMOUNT
            ending_of_line := -1
            if current_line_id != 0 && len(lines) > 1 do ending_of_line = lines[current_line_id - 1].end
            else if cursor_position == len(builder.buf) && current_line_id != 0 {
                ending_of_line = cursor_position - 1
            }
            //NOTE: header_id as the y coord is only true for when all the headers are all 1 screen width long
            cursor_coords = {cursor_position - ending_of_line - 1, header_id}
        }

        {     //Render text
            //TODO: Be able to scroll from top to bottom, such that the file can be bigger
            //than the rendered screen
            for header, header_id in headers {
                using header
                str := strings.to_string(builder)
                color: rl.Color

                switch indentation_level % 4 {
                case 0:
                    color = PURPLE
                case 1:
                    color = RED
                case 2:
                    color = GREEN
                case 3:
                    color = BLUE
                }

                x_offset: i32 = auto_cast indentation_level * INDENTATION_AMOUNT

                DrawCircle(
                    auto_cast text_measure.x / 2. + 2 + x_offset,
                    auto_cast text_measure.y / 2 + auto_cast header_id * auto_cast (text_measure.y + 2),
                    text_measure.x / 3,
                    color,
                )
                //TODO: Render text such that we have newlines, and at some point, some line-wrapping
                DrawTextEx(
                    font,
                    fmt.ctprintf("%v", str),
                    {text_measure.x + 4 + 2 + f32(x_offset), 1 + (text_measure.y + 2) * f32(header_id)},
                    20,
                    0,
                    WHITE,
                )
            }
            //Cursor
            DrawRectangleV(
                 {
                    auto_cast (cursor_coords.x) * text_measure.x +
                    text_measure.x +
                    4 +
                    2 +
                    f32(cursor_x_offset),
                    1 + (text_measure.y + 2) * auto_cast header_id,
                },
                {0.5 * text_measure.x, text_measure.y - 4},
                BLUE,
            )

        }
    }
}

execute_command :: proc(using editor: ^Editor, key: rl.KeyboardKey) {
    switch {

    case key == .BACKSPACE && rl.IsKeyDown(.LEFT_CONTROL):
        using header := headers[header_id]
        using builder
        //delete everything until the cursor meets whitespace
        //TODO: add some checks on cursor_position to stop craches

        if cursor_position == 0 do break
        if strings.is_space(auto_cast buf[cursor_position - 1]) {
            for strings.is_space(auto_cast buf[cursor_position - 1]) && len(buf) != 0 {
                remove_back_byte_at(editor, cursor_position)
                cursor_position -= 1
                cursor_position = max(0, cursor_position)
                if cursor_position == 0 do break
            }
        } else {
            for !strings.is_space(auto_cast buf[cursor_position - 1]) && len(buf) != 0 {
                remove_back_byte_at(editor, cursor_position)
                cursor_position -= 1
                cursor_position = max(0, cursor_position)
                if cursor_position == 0 do break
            }
        }

    case key == .P && rl.IsKeyDown(.LEFT_CONTROL):
        fmt.printf("----------\n")
        print_tree_hierarchy_hihi(headers[:])

    case key == .BACKSPACE:
        if len(headers[header_id].builder.buf) == 0 && header_id != 0 {
            delete_current_header(editor)
            using new_header := headers[header_id]
            //NOTE: +1 because lines don't end with \n anymore lul
            if header_id != 0 {
                if len(lines) > 0 do cursor_position = slice.last(lines[:]).end + 1
                else do cursor_position = 0
            } else {
                if len(lines) > 0 && lines[0].end - lines[0].start > 0 {
                    cursor_position = lines[0].end + 1
                } else do cursor_position = 0
            }
        } else {
            remove_back_byte_at(editor, cursor_position)
            cursor_position -= 1
            cursor_position = max(0, cursor_position)
        }

    case key == .ENTER:
        //TODO: be able to make headers in the middle of the header list, not just appending
        header_id += 1
        append(&headers, make_header(&header_memory_manager))
        cursor_position = 0

        headers[header_id].indentation_level = headers[header_id - 1].indentation_level
        headers[header_id].parent_header = headers[header_id - 1].parent_header

        if headers[header_id].indentation_level > 0 {
            append(&headers[header_id].parent_header.children_headers, headers[header_id])
        }

    //TODO: have enter+shift to make a newline


    case rl.IsKeyDown(.LEFT_ALT) && key == .RIGHT:
        using header := headers[header_id]

        if parent_header != nil {
            //TODO: only one more than previous header 
            indentation_level = min(parent_header.indentation_level + 1, indentation_level + 1)
        } else {
            if header_id > 0 {
                indentation_level += 1
                #reverse for prev_header, id in headers[:header_id] {
                    if prev_header.indentation_level == indentation_level - 1 {
                        parent_header = prev_header
                        break
                    }
                }
                append(&parent_header.children_headers, header)
            }
        }
        //update the indentation of all its children (this is recursive)
        indent_children :: proc(children_headers: []^Header) {
            for &header in children_headers {
                using header
                indentation_level = min(parent_header.indentation_level + 1, indentation_level + 1)
                indent_children(header.children_headers[:])
            }
        }
        indent_children(children_headers[:])

    case rl.IsKeyDown(.LEFT_ALT) && key == .LEFT:
        using header := headers[header_id]
        if parent_header != nil {
            indentation_level = max(0, indentation_level - 1)

            //remove it from parents header children list
            id_child_list := 0

            for &child, id in parent_header.children_headers {
                if child == header do id_child_list = id
            }
            ordered_remove(&parent_header.children_headers, id_child_list)

            defer {
                parent_header = parent_header.parent_header
                if parent_header != nil do append(&parent_header.children_headers, header)
            }

            //unindent children
            unindent_children :: proc(children_headers: []^Header) {
                for &header in children_headers {
                    using header
                    indentation_level = max(parent_header.indentation_level - 1, indentation_level - 1, 0)
                    unindent_children(header.children_headers[:])
                }
            }
            unindent_children(children_headers[:])

            //TODO: Check if the error in the indentation is here or not
            if parent_header == nil do panic("nil parent header")

            if len(parent_header.children_headers) != 0 {
                last_child_header := slice.last(parent_header.children_headers[:])

                max_child_id := -1

                for child in parent_header.children_headers {
                    child_id, ok := slice.linear_search(headers[:], child)
                    if !ok do panic("child not found")
                    max_child_id = max(max_child_id, child_id)
                }

                inject_at(&headers, max_child_id + 1, header)
                ordered_remove(&headers, header_id)
                //NOTE: since we do an ordered remove, it cancels out the +1 from the injection
                header_id = max_child_id
            }
        }

    // When we unindent a header, that header will no longer be a child header
    //to its parent header and might
    // become a new child header for a parent header with a smaller indentation

    case key == .RIGHT:
        using header := headers[header_id]
        cursor_position += 1
        cursor_position = min(cursor_position, len(strings.to_string(builder)))

    case key == .LEFT:
        cursor_position -= 1
        cursor_position = max(0, cursor_position)

    case (key == .D && rl.IsKeyDown(.LEFT_CONTROL)) || key == .DELETE:
        remove_forward_byte_at(editor, cursor_position)
    // no cursor movement with the delete key

    case key == .W && rl.IsKeyDown(.LEFT_CONTROL):
        when HEADERS_ONE_LINE {
            using header := headers[header_id]
            clear(&builder.buf)
            if len(headers) > 1 do delete_current_header(editor)
        } else {
            using header := headers[header_id]
            line_id := get_visual_cursor_line_id(editor^)
            end_line_id := len(lines) - 1 if len(lines) > 1 else -1

            end := lines[line_id].end
            start := lines[line_id].start
            //TODO: refactor a bit (I repeat myself a bit too much)
            if line_id != 0 && line_id != end_line_id {
                cursor_position = start
                length := end - start + 1
                for _ in 0 ..< length {
                    remove_forward_byte_at(editor, cursor_position)
                }
            } else if line_id == 0 {
                if len(lines) == 1 {
                    clear(&builder.buf)
                    cursor_position = 0
                } else {
                    length := end - start + 1
                    cursor_position = 0
                    for _ in 0 ..< length {
                        remove_forward_byte_at(editor, cursor_position)
                    }
                }
            } else if line_id == end_line_id {
                cursor_position = start
                length := end - start
                for _ in 0 ..< length {
                    remove_forward_byte_at(editor, cursor_position)
                }
            } else do panic("can't be here!!!")
        }

    case key == .K && rl.IsKeyDown(.LEFT_CONTROL):
        using header := headers[header_id]
        line_id := get_visual_cursor_line_id(editor^)
        using line := lines[line_id]

        length := end - cursor_position
        if builder.buf[end] != '\n' do length += 1
        for _ in 0 ..< length do remove_forward_byte_at(editor, cursor_position)

    case key == .A && rl.IsKeyDown(.LEFT_CONTROL):
        using header := headers[header_id]
        line_id := get_visual_cursor_line_id(editor^)
        cursor_position = lines[line_id].start

    case key == .E && rl.IsKeyDown(.LEFT_CONTROL):
        using header := headers[header_id]
        line_id := get_visual_cursor_line_id(editor^)
        end := lines[line_id].end
        if builder.buf[end] != '\n' do end += 1
        cursor_position = end

    //TODO: have a menu to open files and a save as option
    case key == .S && rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyDown(.LEFT_SHIFT):
        using header := headers[header_id]
        file_name := "dump.txt"
        fd, err := os.open(file_name, os.O_CREATE)
        if err != os.ERROR_NONE do panic("failed to save file")
        defer os.close(fd)
        _, err1 := os.write_string(fd, strings.to_string(builder))
        if err1 != os.ERROR_NONE do panic("failed to write to file")

    case rl.IsKeyDown(.LEFT_CONTROL) && key == .O:
        using header := headers[header_id]
        delete(builder.buf)
        data, ok := os.read_entire_file_from_filename("dump.txt")
        defer delete(data)
        data_dynamic, ok1 := slice.to_dynamic(data)
        builder.buf = data_dynamic


    //TODO: go between lines and headers depending on if the cursor is at the first/last line of
    //text buffer
    case key == .UP:
        when HEADERS_ONE_LINE {
            header_id = max(0, header_id - 1)
            //TODO: position cursor_position correctly
            //NOTE: maybe the header can keep track of the last postion of the cursor, so when
            //we go back to that cursor, the cursor will go straight back to the last position
            cursor_position = 0
        } else {
            using header := headers[header_id]
            line_id := get_visual_cursor_line_id(editor^)
            if line_id == 0 do return

            // current line is REAL
            if line_id < len(lines) {
                assert(len(lines) > 1)
                current_line := lines[line_id]
                offset_current_line := cursor_position - current_line.start
                new_line := lines[line_id - 1]

                length_newline := new_line.end - new_line.start
                if length_newline >= offset_current_line {
                    cursor_position = new_line.start + offset_current_line
                } else do cursor_position = new_line.end
            } else {
                // no characters in current line
                cursor_position = slice.last(lines[:]).start
            }
        }

    case key == .DOWN:
        when HEADERS_ONE_LINE {
            header_id = min(len(headers) - 1, header_id + 1)
            //TODO: position cursor_position correctly
            cursor_position = 0
        } else {
            using header := headers[header_id]
            line_id := get_visual_cursor_line_id(editor^)
            // VISUAL line              Real line
            if line_id == len(lines) || line_id == len(lines) - 1 do return

            current_line := lines[line_id]
            offset_current_line := cursor_position - current_line.start
            new_line := lines[line_id + 1]

            length_newline: int
            if builder.buf[new_line.end] == '\n' do length_newline = new_line.end - new_line.start
            else do length_newline = new_line.end - new_line.start + 1

            if length_newline >= offset_current_line {
                cursor_position = new_line.start + offset_current_line
            } else do cursor_position = new_line.end
        }

    case is_printable(key):
        using header := headers[header_id]
        byte_to_write := determine_printable_byte(key)
        write_byte(editor, byte_to_write)
        cursor_position += 1
        cursor_position = min(cursor_position, len(strings.to_string(builder)))
    }
}

write_byte :: proc(using editor: ^Editor, byte_to_write: byte) {
    using header := headers[header_id]
    length := strings.builder_len(builder)
    capacity := cap(builder.buf)
    if cursor_position != length && length > 0 {
        strings.write_byte(&builder, 0)
        mem.copy(
            &builder.buf[cursor_position + 1],
            &builder.buf[cursor_position],
            capacity - cursor_position,
        )
        builder.buf[cursor_position] = byte_to_write
    } else do strings.write_byte(&builder, byte_to_write)
}

remove_back_byte_at :: proc(using editor: ^Editor, position: int) {
    using header := headers[header_id]
    if position == 0 do return
    length := len(builder.buf)
    capacity := cap(builder.buf)
    if position == len(builder.buf) do strings.pop_byte(&builder)
    else {
        mem.copy(&builder.buf[position - 1], &builder.buf[position], capacity - position)
        d := cast(^runtime.Raw_Dynamic_Array)&builder.buf
        d.len = max(length - 1, 0)
    }
}

remove_forward_byte_at :: proc(using editor: ^Editor, position: int) {
    using header := headers[header_id]
    if position > len(builder.buf) - 1 do return

    length := len(builder.buf)
    capacity := cap(builder.buf)

    if position == len(builder.buf) - 1 && len(builder.buf) >= 1 {
        d := cast(^runtime.Raw_Dynamic_Array)&builder.buf
        d.len = max(length - 1, 0)
        return
    }

    mem.copy(&builder.buf[position], &builder.buf[position + 1], capacity - (position + 1))
    d := cast(^runtime.Raw_Dynamic_Array)&builder.buf
    d.len = max(length - 1, 0)
}

get_visual_cursor_line_id :: proc(using editor: Editor) -> int {
    using header := headers[header_id]
    if len(lines) == 0 do return 0

    current_line_id := 0
    for line in lines {
        if cursor_position >= line.start {
            end_line_byte := builder.buf[line.end]
            test: int
            if end_line_byte == '\n' do test = line.end
            else do test = line.end + 1

            if cursor_position <= test do break
        }
        current_line_id += 1
    }

    return current_line_id
}

is_printable :: proc(key: rl.KeyboardKey) -> bool {
    key: int = auto_cast key
    return key >= 32 && key <= 127
}

is_alpha :: proc(key: rl.KeyboardKey) -> bool {
    key: int = auto_cast key
    return key >= 65 && key <= 90
}

shift_key_down :: proc() -> bool {
    return rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
}

determine_printable_byte :: proc(key: rl.KeyboardKey) -> (byte_to_write: byte) {
    // Because I don't know how to use raylib GetCharPressed
    assert(is_printable(key))
    switch {
    case is_alpha(key):
        if !shift_key_down() do byte_to_write = (auto_cast key) + 32
        else do byte_to_write = auto_cast key
    case shift_key_down():
        switch {
        case key == .ONE:
            byte_to_write = 33
        case key == .TWO:
            byte_to_write = 64
        case key == .THREE:
            byte_to_write = 35
        case key == .FOUR:
            byte_to_write = 36
        case key == .FIVE:
            byte_to_write = 37
        case key == .SIX:
            byte_to_write = 94
        case key == .SEVEN:
            byte_to_write = 38
        case key == .EIGHT:
            byte_to_write = 42
        case key == .NINE:
            byte_to_write = 40
        case key == .ZERO:
            byte_to_write = 41
        case key == .MINUS:
            byte_to_write = 95
        case key == .EQUAL:
            byte_to_write = 43
        case key == .SLASH:
            byte_to_write = 63
        case key == .APOSTROPHE:
            byte_to_write = 34
        }
    case:
        byte_to_write = auto_cast key
    }

    return
}

print_tree_hierarchy_hihi :: proc(headers: []^Header) {
    context.allocator = context.temp_allocator
    visited_headers := make(map[^Header]bool)

    //TODO: put an id to know who is the parent header
    print_tree_hierarchy :: proc(
        headers: []^Header,
        visited_headers: ^map[^Header]bool,
        indentation_level: int,
        parent_text: string,
    ) {
        for header, id in headers {
            using header
            visited := header in visited_headers
            if !visited {
                visited_headers[header] = true
		//TODO: the printing is not really working here, FIXME
                for _ in 0 ..< indentation_level do fmt.printf("  ")
                if parent_text != "" do fmt.printf("%s ", parent_text)
                else do fmt.printf("parent is nil: ")
                fmt.printf("%v\n", strings.to_string(builder))
                print_tree_hierarchy(
                    children_headers[:],
                    visited_headers,
                    indentation_level + 1,
                    strings.to_string(builder),
                )
            } else do continue
        }
    }
    print_tree_hierarchy(headers[:], &visited_headers, 0, "")
}

//TODO: make the same func print_tree_hierarchy but with without recursion
