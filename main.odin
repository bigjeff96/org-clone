package orgclone

import "core:fmt"
import "core:strings"
import "core:runtime"
import "core:mem"
import rl "vendor:raylib"
import mu "vendor:microui"
import mu_rl "microui_raylib"
import "vendor:stb/src"

cursor_rect := rl.Rectangle{0, 0, 50, 20}

TICK_DURATION :: 30

Editor :: struct {
    cursor_position:      int,
    prev_key:             rl.KeyboardKey,
    tick:                 int,
    builder:              strings.Builder,
    cursor_position_2d:   [2]int,
    position_of_newlines: [dynamic]int,
    font:                 rl.Font,
    text_measure:         rl.Vector2,
    font_size:            int,
}

init_editor :: proc(using editor: ^Editor, font_size_to_use: int) -> mem.Allocator_Error {
    font = rl.LoadFont("FiraCode-Regular.ttf")
    font_size = font_size_to_use
    text_measure = rl.MeasureTextEx(font, "t", auto_cast font_size, 0)
    tick = TICK_DURATION
    builder = strings.builder_make() or_return
    position_of_newlines = make([dynamic]int) or_return
    return .None
}

main :: proc() {
    using rl
    SetWindowState({.MSAA_4X_HINT, .VSYNC_HINT})
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

        {     // count new lines in builder
            clear(&position_of_newlines)
            for char, id in strings.to_string(builder) {
                if char == '\n' do append(&position_of_newlines, id)
            }
        }

        key := rl.GetKeyPressed()
        {     // Update key and reset tick
            prev_key = key if key != .KEY_NULL else prev_key
            if key != .KEY_NULL do tick = TICK_DURATION
        }


        //TODO: (joe) Might need to rework this so that we can do keyboard shortcuts
        command: switch {
        case key == .BACKSPACE:
	    remove_byte(&editor)
            cursor_position -= 1
            cursor_position = max(0, cursor_position)

        case key == .ENTER:
	    write_byte(&editor, '\n')
            cursor_position += 1
	    cursor_position = min(cursor_position, len(strings.to_string(builder)))

        case key == .RIGHT:
            cursor_position += 1
            cursor_position = min(cursor_position, len(strings.to_string(builder)))

        case key == .LEFT:
            cursor_position -= 1
            cursor_position = max(0, cursor_position)

        case key == .KEY_NULL:
            if IsKeyDown(prev_key) {
                if tick > 0 do tick -= 1
                else {
                    switch {
                    case key == .ENTER:
			write_byte(&editor, '\n')
			cursor_position += 1
			cursor_position = min(cursor_position, len(strings.to_string(builder)))

                    case is_printable(prev_key):
                        byte_to_write := determine_printable_byte(key)
			write_byte(&editor, byte_to_write)
                        cursor_position += 1
                        cursor_position = min(cursor_position, len(strings.to_string(builder)))

                    case prev_key == .BACKSPACE:
                        remove_byte(&editor)
                        cursor_position -= 1
                        cursor_position = max(0, cursor_position)

                    case prev_key == .RIGHT:
                        cursor_position += 1
                        cursor_position = min(cursor_position, len(strings.to_string(builder)))

                    case prev_key == .LEFT:
                        cursor_position -= 1
                        cursor_position = max(0, cursor_position)
                    }
                }
            }

        case is_printable(key):
            byte_to_write := determine_printable_byte(key)
	    write_byte(&editor, byte_to_write)
            cursor_position += 1
	    cursor_position = min(cursor_position, len(strings.to_string(builder)))
        }

        nbr_of_lines := 0
	// when on the first line, x_coord = 0
        line_position := -1
	
        for line in position_of_newlines {
            if cursor_position <= line do break
            nbr_of_lines += 1
            line_position = line
        }
        str := strings.to_string(builder)
        //TODO: (joe) Separate by newline and draw each line separatly
        DrawTextEx(font, fmt.ctprintf("%v", str), {0, 0}, 20, 0, WHITE)
        DrawRectangleV(
            {
                auto_cast (cursor_position - line_position - 1) * text_measure.x,
                (text_measure.y + 8.5) * auto_cast nbr_of_lines,
            },
            {0.5 * text_measure.x, text_measure.y},
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
	mem.copy(&builder.buf[cursor_position + 1], &builder.buf[cursor_position], capacity - cursor_position)
	builder.buf[cursor_position] = byte_to_write
    } else do strings.write_byte(&builder, byte_to_write)
}

remove_byte :: proc(using editor: ^Editor) {
    if cursor_position == 0 do return
    length := len(builder.buf)
    capacity := cap(builder.buf)
    if cursor_position == len(builder.buf) do strings.pop_byte(&builder)
    else {
	mem.copy(&builder.buf[cursor_position - 1], &builder.buf[cursor_position], capacity - cursor_position)
	d := cast(^runtime.Raw_Dynamic_Array)&builder.buf
	d.len = max(length - 1, 0)
    }
}
