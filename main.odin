package orgclone

import "core:fmt"
import "core:strings"
import "core:runtime"
import "core:mem"
import "core:slice"
import "core:os"
import rl "vendor:raylib"
import mu "vendor:microui"
import mu_rl "microui_raylib"
import "vendor:stb/src"

TICK_DURATION :: 15

Line :: struct {
    start: int,
    end:   int,
}

Editor :: struct {
    cursor_position: int,
    prev_key:        rl.KeyboardKey,
    tick:            int,
    builder:         strings.Builder,
    lines:           [dynamic]Line,
    font:            rl.Font,
    text_measure:    rl.Vector2,
    font_size:       int,
}

Header :: struct {
    state: enum {
	todo,
	done,
	waiting,
    },
    parent_header: ^Header,
    children_headers: [dynamic]^Header,
    text: strings.Builder,
    tags: enum {
	A,
	B,
	C,
    },
}

init_editor :: proc(using editor: ^Editor, font_size_to_use: int) -> mem.Allocator_Error {
    font = rl.LoadFont("FiraCode-Regular.ttf")
    font_size = font_size_to_use
    text_measure = rl.MeasureTextEx(font, "t", auto_cast font_size, 0)
    tick = TICK_DURATION
    builder = strings.builder_make() or_return
    lines = make([dynamic]Line) or_return
    return .None
}

main :: proc() {
    using rl
    SetWindowState({.MSAA_4X_HINT, .VSYNC_HINT, .WINDOW_RESIZABLE})
    SetTargetFPS(60)
    InitWindow(800, 800, "org-clone")
    defer CloseWindow()

    ctx := mu_rl.raylib_cxt()
    editor: Editor
    err := init_editor(&editor, 20)
    if err != .None do panic("error in editor allocation")
    using editor

    for !WindowShouldClose() {
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

        execute_command :: proc(using editor: ^Editor, key: rl.KeyboardKey) {
            switch {
            case key == .BACKSPACE:
                remove_back_byte_at(editor, cursor_position)
                cursor_position -= 1
                cursor_position = max(0, cursor_position)

            case key == .ENTER:
                write_byte(editor, '\n')
                cursor_position += 1
                cursor_position = min(cursor_position, len(strings.to_string(builder)))

            case key == .RIGHT:
                cursor_position += 1
                cursor_position = min(cursor_position, len(strings.to_string(builder)))

            case key == .LEFT:
                cursor_position -= 1
                cursor_position = max(0, cursor_position)

            case (key == .D && rl.IsKeyDown(.LEFT_CONTROL)) || key == .DELETE:
                remove_forward_byte_at(editor, cursor_position)
            // no cursor movement with the delete key

            case key == .W && rl.IsKeyDown(.LEFT_CONTROL):
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

            case key == .K && rl.IsKeyDown(.LEFT_CONTROL):
                line_id := get_visual_cursor_line_id(editor^)
                using line := lines[line_id]

                length := end - cursor_position
                if builder.buf[end] != '\n' do length += 1
                for _ in 0 ..< length do remove_forward_byte_at(editor, cursor_position)

            case key == .A && rl.IsKeyDown(.LEFT_CONTROL):
                line_id := get_visual_cursor_line_id(editor^)
                cursor_position = lines[line_id].start

            case key == .E && rl.IsKeyDown(.LEFT_CONTROL):
                line_id := get_visual_cursor_line_id(editor^)
                end := lines[line_id].end
                if builder.buf[end] != '\n' do end += 1
                cursor_position = end

            //TODO: have a menu to open files and a save as option
            case key == .S && rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyDown(.LEFT_SHIFT):
                file_name := "dump.txt"
                fd, err := os.open(file_name, os.O_CREATE)
                if err != os.ERROR_NONE do panic("failed to save file")
                defer os.close(fd)
                _, err1 := os.write_string(fd, strings.to_string(builder))
                if err1 != os.ERROR_NONE do panic("failed to write to file")

            case rl.IsKeyDown(.LEFT_CONTROL) && key == .O:
                delete(builder.buf)
                data, ok := os.read_entire_file_from_filename("dump.txt")
                defer delete(data)
                data_dynamic, ok1 := slice.to_dynamic(data)
                builder.buf = data_dynamic

            //TODO: deleting words with ctrl + backspace & ctrl + delete

            case key == .UP:
                line_id := get_visual_cursor_line_id(editor^)
                if line_id == 0 do return

                // current line is REAL
                if line_id < len(lines) {
                    assert(len(lines) > 1)
                    current_line := lines[line_id]
                    offset_current_line := cursor_position - current_line.start
                    new_line := lines[line_id - 1]

                    length_newline := new_line.end - new_line.start
                    if length_newline >= offset_current_line do cursor_position = new_line.start + offset_current_line
                    else do cursor_position = new_line.end
                } else {
                    // no characters in current line
                    cursor_position = slice.last(lines[:]).start
                }

            case key == .DOWN:
                line_id := get_visual_cursor_line_id(editor^)
                // VISUAL line              Real line
                if line_id == len(lines) || line_id == len(lines) - 1 do return

                current_line := lines[line_id]
                offset_current_line := cursor_position - current_line.start
                new_line := lines[line_id + 1]

                length_newline: int = new_line.end - new_line.start if builder.buf[new_line.end] == '\n' else new_line.end - new_line.start + 1
                if length_newline >= offset_current_line do cursor_position = new_line.start + offset_current_line
                else do cursor_position = new_line.end

            case is_printable(key):
                byte_to_write := determine_printable_byte(key)
                write_byte(editor, byte_to_write)
                cursor_position += 1
                cursor_position = min(cursor_position, len(strings.to_string(builder)))
            }
        }

        if key != .KEY_NULL do execute_command(&editor, key)
        else {
            if IsKeyDown(prev_key) {
                if tick > 0 do tick -= 1
                else do execute_command(&editor, prev_key)
            }
        }

        {     // determine lines in builder
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
        {
            current_line_id := get_visual_cursor_line_id(editor)
            ending_of_line := -1
            if current_line_id != 0 && len(lines) > 1 do ending_of_line = lines[current_line_id - 1].end
            else if cursor_position == len(builder.buf) && current_line_id != 0 do ending_of_line = cursor_position - 1
            cursor_coords = {cursor_position - ending_of_line - 1, current_line_id}
        }

        str := strings.to_string(builder)
        //TODO: (joe) Separate by newline and draw each line separatly
        DrawTextEx(font, fmt.ctprintf("%v", str), {0, 0}, 20, 0, WHITE)
        DrawRectangleV(
            {
                auto_cast (cursor_coords.x) * text_measure.x,
                1 + (text_measure.y + 10) * auto_cast cursor_coords.y,
            },
            {0.5 * text_measure.x, text_measure.y - 4},
            BLUE,
        )
    }
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

write_byte :: proc(using editor: ^Editor, byte_to_write: byte) {
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
    if position >= len(builder.buf) - 1 do return
    length := len(builder.buf)
    capacity := cap(builder.buf)

    mem.copy(&builder.buf[position], &builder.buf[position + 1], capacity - (position + 1))

}

get_visual_cursor_line_id :: proc(using editor: Editor) -> int {
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
