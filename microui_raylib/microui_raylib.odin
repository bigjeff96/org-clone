package micro_ui_raylib

import "core:fmt"
import "core:unicode/utf8"
import "core:strings"
import rl "vendor:raylib"
import mu "vendor:microui"

FONT_SIZE_MU :: 25
ui_state := struct {
    mu_ctx:          mu.Context,
    log_buf:         [1 << 16]byte,
    pixels_of_image: [][4]u8,
    log_buf_len:     int,
    log_buf_updated: bool,
    bg:              mu.Color,
    atlas_texture:   rl.Texture2D,
} {
    bg = {90, 95, 100, 255},
}

@(deferred_none = deinit_raylib_cxt)
raylib_cxt :: proc() -> (ctx: ^mu.Context) {

    pixels := make([][4]u8, mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT)
    for alpha, i in mu.default_atlas_alpha {
        pixels[i] = {0xff, 0xff, 0xff, alpha}
    }

    ui_state.pixels_of_image = pixels[:]

    image := rl.Image {
        data    = raw_data(pixels),
        width   = mu.DEFAULT_ATLAS_WIDTH,
        height  = mu.DEFAULT_ATLAS_HEIGHT,
        mipmaps = 1,
        format  = .UNCOMPRESSED_R8G8B8A8,
    }
    ui_state.atlas_texture = rl.LoadTextureFromImage(image)

    ctx = &ui_state.mu_ctx
    mu.init(ctx)
    ctx.text_width = rl_text_width
    ctx.text_height = rl_text_height
    ctx.style.spacing += 3
    return
}

deinit_raylib_cxt :: proc() {
    rl.UnloadTexture(ui_state.atlas_texture)
    delete(ui_state.pixels_of_image)
}

mu_font :: #force_inline proc(font: int) -> mu.Font {
    return mu.Font(uintptr(FONT_SIZE_MU))
}

mu_input :: proc(ctx: ^mu.Context) {
    mu_text_input(ctx)
    mu_mouse_input(ctx)
    mu_keyboard_input(ctx)
}

mu_text_input :: proc(ctx: ^mu.Context) {
    text_input: [512]byte = ---
    text_input_offset := 0
    for text_input_offset < len(text_input) {
        ch := rl.GetCharPressed()
        if ch == 0 {
            break
        }
        b, w := utf8.encode_rune(ch)
        copy(text_input[text_input_offset:], b[:w])
        text_input_offset += w
    }
    mu.input_text(ctx, string(text_input[:text_input_offset]))
}

mu_mouse_input :: proc(ctx: ^mu.Context) {
    mouse_pos := [2]i32{rl.GetMouseX(), rl.GetMouseY()}
    mu.input_mouse_move(ctx, mouse_pos.x, mouse_pos.y)
    mu.input_scroll(ctx, 0, i32(rl.GetMouseWheelMove() * -30))

    @(static)
    buttons_to_key := [?]struct {
        rl_button: rl.MouseButton,
        mu_button: mu.Mouse,
    }{{.LEFT, .LEFT}, {.RIGHT, .RIGHT}, {.MIDDLE, .MIDDLE}}
    for button in buttons_to_key {
        if rl.IsMouseButtonPressed(button.rl_button) {
            mu.input_mouse_down(ctx, mouse_pos.x, mouse_pos.y, button.mu_button)
        } else if rl.IsMouseButtonReleased(button.rl_button) {
            mu.input_mouse_up(ctx, mouse_pos.x, mouse_pos.y, button.mu_button)
        }
    }
}

mouse_in_ui :: proc(ctx: ^mu.Context) -> bool {
    for container in ctx.containers do if container.open {
        using container
        if mu.rect_overlaps_vec2(rect, ctx.mouse_pos) do return true
    }
    return false
}

mu_keyboard_input :: proc(ctx: ^mu.Context) {
    @(static)
    keys_to_check := [?]struct {
        rl_key: rl.KeyboardKey,
        mu_key: mu.Key,
    }{{
            .LEFT_SHIFT,
            .SHIFT,
        }, {.RIGHT_SHIFT, .SHIFT}, {.LEFT_CONTROL, .CTRL}, {.RIGHT_CONTROL, .CTRL}, {.LEFT_ALT, .ALT}, {.RIGHT_ALT, .ALT}, {.ENTER, .RETURN}, {.KP_ENTER, .RETURN}, {.BACKSPACE, .BACKSPACE}}

    for key in keys_to_check {
        if rl.IsKeyPressed(key.rl_key) {
            mu.input_key_down(ctx, key.mu_key)
        } else if rl.IsKeyReleased(key.rl_key) {
            mu.input_key_up(ctx, key.mu_key)
        }
    }
}

render :: proc(ctx: ^mu.Context) {
    render_texture :: proc(rect: mu.Rect, pos: [2]i32, color: mu.Color) {
        source := rl.Rectangle{f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)}
        position := rl.Vector2{f32(pos.x), f32(pos.y)}

        rl.DrawTextureRec(ui_state.atlas_texture, source, position, transmute(rl.Color)color)
    }

    rl.BeginScissorMode(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight())
    defer rl.EndScissorMode()

    command_backing: ^mu.Command
    for variant in mu.next_command_iterator(ctx, &command_backing) {
        switch cmd in variant {
        case ^mu.Command_Text:
            pos := [2]i32{cmd.pos.x, cmd.pos.y}
            cstr := strings.clone_to_cstring(cmd.str, context.temp_allocator)
            /* width := rl.MeasureText(cstr, FONT_SIZE) */
            width := ctx.text_width(mu_font(FONT_SIZE_MU), cmd.str)
            rl.DrawText(cstr, pos.x, pos.y - 3, FONT_SIZE_MU, transmute(rl.Color)cmd.color)
            pos.x += width
        case ^mu.Command_Rect:
            rl.DrawRectangle(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h, transmute(rl.Color)cmd.color)
        case ^mu.Command_Icon:
            rect := mu.default_atlas[cmd.id]
            x := cmd.rect.x + (cmd.rect.w - rect.w) / 2
            y := cmd.rect.y + (cmd.rect.h - rect.h) / 2
            render_texture(rect, {x, y}, cmd.color)
        case ^mu.Command_Clip:
            rl.EndScissorMode()
            rl.BeginScissorMode(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h)
        case ^mu.Command_Jump:
            unreachable()
        }
    }
}

u8_slider :: proc(ctx: ^mu.Context, val: ^u8, lo, hi: u8) -> (res: mu.Result_Set) {
    mu.push_id(ctx, uintptr(val))

    @(static)
    tmp: mu.Real
    tmp = mu.Real(val^)
    res = mu.slider(ctx, &tmp, mu.Real(lo), mu.Real(hi), 0, "%.0f", {.ALIGN_CENTER})
    val^ = u8(tmp)
    mu.pop_id(ctx)
    return
}

int_slider :: proc(
    ctx: ^mu.Context,
    value_int: ^int,
    low, high: int,
    step: int,
    fmt_str: string,
) -> (
    res: mu.Result_Set,
) {
    @(static)
    value_int_real: mu.Real
    mu.push_id(ctx, uintptr(value_int))
    value_int_real = mu.Real(value_int^)
    res = mu.slider(ctx, &value_int_real, auto_cast low, auto_cast high, 1, fmt_str)
    value_int^ = int(value_int_real)
    mu.pop_id(ctx)
    return
}

title_seperator :: proc(ctx: ^mu.Context, title: string, color: mu.Color = {0, 0, 0, 255}) {
    mu.layout_row(ctx, {20, ctx.text_width(mu_font(FONT_SIZE_MU), title) + ctx.style.padding * 2, -1})
    rect := mu.layout_next(ctx)
    rect.h = 5
    rect.y += ctx.text_height(mu_font(FONT_SIZE_MU)) / 2 + 5
    mu.draw_rect(ctx, rect, color)
    mu.label(ctx, title)
    rect = mu.layout_next(ctx)
    rect.h = 5
    rect.y += ctx.text_height(mu_font(FONT_SIZE_MU)) / 2 + 5
    mu.draw_rect(ctx, rect, color)
}

write_log :: proc(str: string) {
    ui_state.log_buf_len += copy(ui_state.log_buf[ui_state.log_buf_len:], str)
    ui_state.log_buf_len += copy(ui_state.log_buf[ui_state.log_buf_len:], "\n")
    ui_state.log_buf_updated = true
}

read_log :: proc() -> string {
    return string(ui_state.log_buf[:ui_state.log_buf_len])
}

reset_log :: proc() {
    ui_state.log_buf_updated = true
    ui_state.log_buf_len = 0
}

rl_text_height :: proc(font: mu.Font) -> i32 {
    using rl
    return(
        auto_cast MeasureTextEx(GetFontDefault(), strings.clone_to_cstring("Test test yyyy ppp gggQPPKK", context.temp_allocator), FONT_SIZE_MU, 1).y -
        10 \
    )
}

rl_text_width :: proc(font: mu.Font, text: string) -> (width: i32) {
    using rl
    csrt := strings.clone_to_cstring(text, context.temp_allocator)
    return MeasureText(csrt, i32(uintptr(font)))
}

demo_reel :: proc(ctx: ^mu.Context) {
    @(static)
    opts := mu.Options{.NO_CLOSE, .ALIGN_CENTER}

    if mu.window(ctx, "Demo Window", {rl.GetScreenWidth() / 2, rl.GetScreenHeight() / 2, 300, 450}, opts) {
        if .ACTIVE in mu.header(ctx, "Window Info") {
            win := mu.get_current_container(ctx)
            mu.layout_row(ctx, {54, -1}, 0)
            mu.label(ctx, "Position:")
            mu.label(ctx, fmt.tprintf("%d, %d", win.rect.x, win.rect.y))
            mu.label(ctx, "Size:")
            mu.label(ctx, fmt.tprintf("%d, %d", win.rect.w, win.rect.h))
        }

        if .ACTIVE in mu.header(ctx, "Window Options") {
            mu.layout_row(ctx, {120, 120, 120}, 0)
            for opt in mu.Opt {
                state := opt in opts
                if .CHANGE in mu.checkbox(ctx, fmt.tprintf("%v", opt), &state) {
                    if state {
                        opts += {opt}
                    } else {
                        opts -= {opt}
                    }
                }
            }
        }

        if .ACTIVE in mu.header(ctx, "Test Buttons", {.EXPANDED}) {
            mu.layout_row(ctx, {120, -85, -1})
            mu.label(ctx, "Test buttons 1:")
            if .SUBMIT in mu.button(ctx, "Button 1") {write_log("Pressed button 1")}
            if .SUBMIT in mu.button(ctx, "Button 2") {write_log("Pressed button 2")}
            mu.label(ctx, "Test buttons 2:")
            if .SUBMIT in mu.button(ctx, "Button 3") {write_log("Pressed button 3")}
            if .SUBMIT in mu.button(ctx, "Button 4") {write_log("Pressed button 4")}
        }

        if .ACTIVE in mu.header(ctx, "Tree and Text", {.EXPANDED}) {
            mu.layout_row(ctx, {140, -1})
            mu.layout_begin_column(ctx)
            if .ACTIVE in mu.treenode(ctx, "Test 1") {
                if .ACTIVE in mu.treenode(ctx, "Test 1a") {
                    mu.label(ctx, "Hello")
                    mu.label(ctx, "world")
                }
                if .ACTIVE in mu.treenode(ctx, "Test 1b") {
                    if .SUBMIT in mu.button(ctx, "Button 1") {write_log("Pressed button 1")}
                    if .SUBMIT in mu.button(ctx, "Button 2") {write_log("Pressed button 2")}
                }
            }
            if .ACTIVE in mu.treenode(ctx, "Test 2") {
                mu.layout_row(ctx, {53, 53})
                if .SUBMIT in mu.button(ctx, "Button 3") {write_log("Pressed button 3")}
                if .SUBMIT in mu.button(ctx, "Button 4") {write_log("Pressed button 4")}
                if .SUBMIT in mu.button(ctx, "Button 5") {write_log("Pressed button 5")}
                if .SUBMIT in mu.button(ctx, "Button 6") {write_log("Pressed button 6")}
            }
            if .ACTIVE in mu.treenode(ctx, "Test 3") {
                @(static)
                checks := [3]bool{true, false, true}
                mu.checkbox(ctx, "Checkbox 1", &checks[0])
                mu.checkbox(ctx, "Checkbox 2", &checks[1])
                mu.checkbox(ctx, "Checkbox 3", &checks[2])

            }
            mu.layout_end_column(ctx)

            mu.layout_begin_column(ctx)
            mu.layout_row(ctx, {-1})
            mu.text(
                ctx,
                "Lorem ipsum dolor sit amet, consectetur adipiscing " +
                "elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus " +
                "ipsum, eu varius magna felis a nulla.",
            )
            mu.layout_end_column(ctx)
        }

        if .ACTIVE in mu.header(ctx, "Background Colour", {.EXPANDED}) {
            mu.layout_row(ctx, {-100, -1}, 68)
            mu.layout_begin_column(ctx)
            {
                mu.layout_row(ctx, {46, -1}, 0)
                mu.label(ctx, "Red:");u8_slider(ctx, &ui_state.bg.r, 0, 255)
                mu.label(ctx, "Green:");u8_slider(ctx, &ui_state.bg.g, 0, 255)
                mu.label(ctx, "Blue:");u8_slider(ctx, &ui_state.bg.b, 0, 255)
            }
            mu.layout_end_column(ctx)

            r := mu.layout_next(ctx)
            mu.draw_rect(ctx, r, ui_state.bg)
            mu.draw_box(ctx, mu.expand_rect(r, 1), ctx.style.colors[.BORDER])
            mu.draw_control_text(
                ctx,
                fmt.tprintf("#%02x%02x%02x", ui_state.bg.r, ui_state.bg.g, ui_state.bg.b),
                r,
                .TEXT,
                {.ALIGN_CENTER},
            )
        }
    }

    when false {
        if mu.window(ctx, "Log Window", {350, 40, 300, 200}, opts) {
            mu.layout_row(ctx, {-1}, -28)
            mu.begin_panel(ctx, "Log")
            mu.layout_row(ctx, {-1}, -1)
            mu.text(ctx, read_log())
            if ui_state.log_buf_updated {
                panel := mu.get_current_container(ctx)
                panel.scroll.y = panel.content_size.y
                ui_state.log_buf_updated = false
            }
            mu.end_panel(ctx)

            @(static)
            buf: [128]byte
            @(static)
            buf_len: int
            submitted := false
            mu.layout_row(ctx, {-70, -1})
            if .SUBMIT in mu.textbox(ctx, buf[:], &buf_len) {
                mu.set_focus(ctx, ctx.last_id)
                submitted = true
            }
            if .SUBMIT in mu.button(ctx, "Submit") {
                submitted = true
            }
            if submitted {
                write_log(string(buf[:buf_len]))
                buf_len = 0
            }
        }
    }


    if mu.window(ctx, "Style Window", {350, 250, 300, 240}) {
        @(static)
        colors := [mu.Color_Type]string {
            .TEXT         = "text",
            .BORDER       = "border",
            .WINDOW_BG    = "window bg",
            .TITLE_BG     = "title bg",
            .TITLE_TEXT   = "title text",
            .PANEL_BG     = "panel bg",
            .BUTTON       = "button",
            .BUTTON_HOVER = "button hover",
            .BUTTON_FOCUS = "button focus",
            .BASE         = "base",
            .BASE_HOVER   = "base hover",
            .BASE_FOCUS   = "base focus",
            .SCROLL_BASE  = "scroll base",
            .SCROLL_THUMB = "scroll thumb",
        }

        sw := i32(f32(mu.get_current_container(ctx).body.w) * 0.14)
        mu.layout_row(ctx, {80, sw, sw, sw, sw, -1})
        for label, col in colors {
            mu.label(ctx, label)
            u8_slider(ctx, &ctx.style.colors[col].r, 0, 255)
            u8_slider(ctx, &ctx.style.colors[col].g, 0, 255)
            u8_slider(ctx, &ctx.style.colors[col].b, 0, 255)
            u8_slider(ctx, &ctx.style.colors[col].a, 0, 255)
            mu.draw_rect(ctx, mu.layout_next(ctx), ctx.style.colors[col])
        }
    }
}
