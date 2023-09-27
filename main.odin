package orgclone

import "core:fmt"
import "core:strings"
import "core:mem"
import rl "vendor:raylib"
import mu "vendor:microui"
import mu_rl "microui_raylib"
import "vendor:stb/src"

cursor_rect := rl.Rectangle{0, 0, 50, 20}

TICK_DURATION :: 30

cursor_position := 0

Editor :: struct {
    cursor_position: int,
    prev_key: rl.KeyboardKey,
    tick: int,
    builder: strings.Builder,
    cursor_position_2d: [2]int,
    position_of_newlines: [dynamic]int,
    font: rl.Font,
    text_measure: rl.Vector2,
    font_size: int
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
    using rl, strings
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
        @(static)
        prev_key: rl.KeyboardKey

        key := rl.GetKeyPressed()

        {     // count new lines in builder
            clear(&position_of_newlines)
            for char, id in strings.to_string(builder) {
                if char == '\n' do append(&position_of_newlines, id)
            }
        }

        if key != .KEY_NULL && tick <= 0 do tick = TICK_DURATION
	//TODO: (joe) Might need to rework this so that we can do keyboard shortcuts
        switch {
        case key == .BACKSPACE:
            strings.pop_byte(&builder)
            prev_key = key
            cursor_position -= 1
	    tick = TICK_DURATION

        case key == .ENTER:
            strings.write_byte(&builder, '\n')
            cursor_position += 1
            prev_key = key
	    tick = TICK_DURATION
        case key == .RIGHT:
            cursor_position += 1
            prev_key = key
            cursor_position = min(cursor_position, len(strings.to_string(builder)))
	    tick = TICK_DURATION
        case key == .LEFT:
            cursor_position -= 1
            prev_key = key
            cursor_position = max(0, cursor_position)
	    tick = TICK_DURATION

        case key == .KEY_NULL:
            if IsKeyDown(prev_key) {
                if tick > 0 do tick -= 1
                else {
                    switch {
                    case key == .ENTER:
                        strings.write_byte(&builder, '\n')

                    case is_printable(prev_key):
                        write_char_to_buffer(&builder, prev_key)
                        cursor_position += 1
                        cursor_position = min(cursor_position, len(strings.to_string(builder)))

                    case prev_key == .BACKSPACE:
                        strings.pop_byte(&builder)
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
            write_char_to_buffer(&builder, key)
            prev_key = key
            cursor_position += 1
	    tick = TICK_DURATION
        }

        nbr_of_lines := 0
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

write_char_to_buffer :: proc(builder: ^strings.Builder, key: rl.KeyboardKey) {
    if is_printable(key) {
        switch {
        case is_alpha(key):
            if !shift_key_down() do strings.write_byte(builder, (auto_cast key) + 32)
            else do strings.write_byte(builder, auto_cast key)
        case shift_key_down():
            switch {
            case key == .ONE:
                strings.write_byte(builder, 33)
            case key == .TWO:
                strings.write_byte(builder, 64)
            case key == .THREE:
                strings.write_byte(builder, 35)
            case key == .FOUR:
                strings.write_byte(builder, 36)
            case key == .FIVE:
                strings.write_byte(builder, 37)
            case key == .SIX:
                strings.write_byte(builder, 94)
            case key == .SEVEN:
                strings.write_byte(builder, 38)
            case key == .EIGHT:
                strings.write_byte(builder, 42)
            case key == .NINE:
                strings.write_byte(builder, 40)
            case key == .ZERO:
                strings.write_byte(builder, 41)
            case key == .MINUS:
                strings.write_byte(builder, 95)
            case key == .EQUAL:
                strings.write_byte(builder, 43)
            case key == .SLASH:
                strings.write_byte(builder, 63)
            case key == .APOSTROPHE:
                strings.write_byte(builder, 34)
            }
        case:
            strings.write_byte(builder, auto_cast key)
        }
    }
}
