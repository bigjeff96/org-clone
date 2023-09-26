package orgclone

import "core:fmt"
import "core:strings"
import "core:mem"
import rl "vendor:raylib"
import mu "vendor:microui"
import mu_rl "microui_raylib"
import "vendor:stb/src"

cursor_rect := rl.Rectangle{0, 0, 50, 20}

TICK_DURATION :: 70

cursor_position := 0

main :: proc() {
    using rl, strings
    SetWindowState({.MSAA_4X_HINT, .VSYNC_HINT})
    SetTargetFPS(60)
    InitWindow(800, 800, "org-clone")
    defer CloseWindow()

    buffer := strings.builder_make()
    defer strings.builder_destroy(&buffer)

    font := LoadFont("FiraCode-Regular.ttf")
    defer UnloadFont(font)
    text_measure := MeasureTextEx(font, "t", 20, 0)

    ctx := mu_rl.raylib_cxt()
    tick := TICK_DURATION
    position_of_newlines := make([dynamic]int)

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

        {     // count new lines in buffer
            clear(&position_of_newlines)
            for char, id in strings.to_string(buffer) {
                if char == '\n' do append(&position_of_newlines, id)
            }
        }

        if key != .KEY_NULL && tick <= 0 do tick = TICK_DURATION
        switch {
        case key == .BACKSPACE:
            strings.pop_byte(&buffer)
            prev_key = key
            cursor_position -= 1

        case key == .ENTER:
            strings.write_byte(&buffer, '\n')
            cursor_position += 1
            prev_key = key
        case key == .RIGHT:
            cursor_position += 1
            prev_key = key
            cursor_position = min(cursor_position, len(strings.to_string(buffer)))
        case key == .LEFT:
            cursor_position -= 1
            prev_key = key
            cursor_position = max(0, cursor_position)

        case key == .KEY_NULL:
            if IsKeyDown(prev_key) {
                if tick > 0 do tick -= 1
                else {
                    switch {
                    case key == .ENTER:
                        strings.write_byte(&buffer, '\n')

                    case is_printable(prev_key):
                        write_char_to_buffer(&buffer, prev_key)
                        cursor_position += 1
                        cursor_position = min(cursor_position, len(strings.to_string(buffer)))

                    case prev_key == .BACKSPACE:
                        strings.pop_byte(&buffer)
                        cursor_position -= 1
                        cursor_position = max(0, cursor_position)

                    case prev_key == .RIGHT:
                        cursor_position += 1
                        cursor_position = min(cursor_position, len(strings.to_string(buffer)))

                    case prev_key == .LEFT:
                        cursor_position -= 1
                        cursor_position = max(0, cursor_position)
                    }
                }
            }

        case is_printable(key):
            write_char_to_buffer(&buffer, key)
            prev_key = key
            cursor_position += 1
        }

        nbr_of_lines := 0
        line_position := -1
        for line in position_of_newlines {
            if cursor_position <= line do break
            nbr_of_lines += 1
            line_position = line
        }
        str := strings.to_string(buffer)
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

write_char_to_buffer :: proc(buffer: ^strings.Builder, key: rl.KeyboardKey) {
    if is_printable(key) {
        switch {
        case is_alpha(key):
            if !shift_key_down() do strings.write_byte(buffer, (auto_cast key) + 32)
            else do strings.write_byte(buffer, auto_cast key)
        case shift_key_down():
            switch {
            case key == .ONE:
                strings.write_byte(buffer, 33)
            case key == .TWO:
                strings.write_byte(buffer, 64)
            case key == .THREE:
                strings.write_byte(buffer, 35)
            case key == .FOUR:
                strings.write_byte(buffer, 36)
            case key == .FIVE:
                strings.write_byte(buffer, 37)
            case key == .SIX:
                strings.write_byte(buffer, 94)
            case key == .SEVEN:
                strings.write_byte(buffer, 38)
            case key == .EIGHT:
                strings.write_byte(buffer, 42)
            case key == .NINE:
                strings.write_byte(buffer, 40)
            case key == .ZERO:
                strings.write_byte(buffer, 41)
            case key == .MINUS:
                strings.write_byte(buffer, 95)
            case key == .EQUAL:
                strings.write_byte(buffer, 43)
            case key == .SLASH:
                strings.write_byte(buffer, 63)
            case key == .APOSTROPHE:
                strings.write_byte(buffer, 34)

            }
        case:
            strings.write_byte(buffer, auto_cast key)
        }
    }
}
