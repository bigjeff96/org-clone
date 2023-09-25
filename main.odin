package orgclone

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import mu "vendor:microui"
import mu_rl "microui_raylib"
import "vendor:stb/src"

cursor_rect := rl.Rectangle{0, 0, 50, 20}

TICK_DURATION :: 70

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

        if key != .KEY_NULL && tick <= 0 do tick = TICK_DURATION
        #partial switch key {
        case .A ..= .Z:
            if !(IsKeyDown(.LEFT_SHIFT) || IsKeyDown(.RIGHT_SHIFT)) {
                strings.write_byte(&buffer, (auto_cast key) + 32)
            } else do strings.write_byte(&buffer, auto_cast key)
            prev_key = key
        case .SPACE:
            strings.write_byte(&buffer, ' ')
            prev_key = key
        case .BACKSPACE:
            strings.pop_byte(&buffer)
            prev_key = key
        case .ENTER:
            strings.write_byte(&buffer, '\n')
            prev_key = key
        case .KEY_NULL:
            if IsKeyDown(prev_key) {
                if tick > 0 do tick -= 1
                else {
                    #partial switch prev_key {
                    case .A ..= .Z:
                        if !(IsKeyDown(.LEFT_SHIFT) || IsKeyDown(.RIGHT_SHIFT)) {
                            strings.write_byte(&buffer, (auto_cast prev_key) + 32)
                        } else do strings.write_byte(&buffer, auto_cast prev_key)

                    case .BACKSPACE:
                        strings.pop_byte(&buffer)

                    case .SPACE:
                        strings.write_byte(&buffer, ' ')
                    }

                }

            }
        }

        str := strings.to_string(buffer)
        DrawTextEx(font, fmt.ctprintf("%v", str), {0, 0}, 20, 0, WHITE)
        length_str := len(str)
        DrawRectangleV(
            {auto_cast length_str * text_measure.x, 0},
            {0.5 * text_measure.x, text_measure.y},
            BLUE,
        )
    }
}
