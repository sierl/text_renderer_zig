const std = @import("std");
const ft = @import("freetype");
const hb = @import("harfbuzz");
const rl = @import("raylib");
const icu = @import("icu_hack.zig");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    std.debug.print("हिन्दी\n", .{});

    // const text = "hello नमस्ते cześć もしもし اتجاه привіт 안녕 مرحبًا 👋😀🎷🇯🇵☝🏾";
    const text = "चूंकि मानव अधिकारों के प्रति उपेक्षा";

    const font_size = 28;

    var font_mgr = try FontMgr.init(allocator);
    defer font_mgr.deinit();

    try font_mgr.load_font("./asset/NotoSans-Regular.ttf", font_size);
    try font_mgr.load_font("./asset/NotoSansArabic-Regular.ttf", font_size);
    try font_mgr.load_font("./asset/NotoEmoji-Regular.ttf", font_size);
    try font_mgr.load_font("./asset/NotoSansJP-Regular.ttf", font_size);
    try font_mgr.load_font("./asset/NotoSansKR-Regular.ttf", font_size);

    const utf16_text = try std.unicode.utf8ToUtf16LeAlloc(allocator, text);
    defer allocator.free(utf16_text);

    var bidi = try BiDi.init(text, allocator);
    defer bidi.deinit();

    var iter = try bidi.visual_runs();
    while (iter.next()) |run| {
        const sl = text[@intCast(run.start)..@intCast(run.end)];
        std.debug.print("({s}): '{s}'\n", .{ if (run.level % 2 == 1) "RTL" else "LTR", sl });
    }

    std.debug.print("--------------------------------------------------------\n", .{});

    var script_iter = try ScriptRunIterator.init(text);
    while (try script_iter.next()) |run| {
        std.debug.print("[{any}]: '{s}'\n", .{ run.script, text[run.start..run.end] });
    }

    std.debug.print("--------------------------------------------------------\n", .{});

    var items: std.ArrayList(Item) = .empty;

    var it = try Itemizer.init(&bidi, text);
    while (try it.next()) |item| {
        std.debug.print("[{d}..{d}) '{s}' {any} {s}\n", .{
            item.start,
            item.start + item.length,
            text[item.start..(item.start + item.length)],
            item.script,
            if (item.is_rtl()) "RTL" else "LTR",
        });

        try items.append(allocator, item);
    }

    const width = 1280;
    const height = 720;
    const framebuffer = try allocator.alloc(Pixel, width * height);
    defer allocator.free(framebuffer);

    @memset(framebuffer, Pixel{ .r = 0, .g = 0, .b = 0, .a = 255 });

    var shaped_runs: std.ArrayList(ShapedRun) = .empty;

    std.debug.print("--------------------------------------------------------\n", .{});
    for (items.items) |*item| {
        const shaped_run = try ShapedRun.init(text, item, &font_mgr);
        // defer shaped_run.deinit();
        try shaped_runs.append(allocator, shaped_run);

        std.debug.print("'{s}'\n", .{text[shaped_run.run.start..(shaped_run.run.start + shaped_run.run.length)]});
    }

    try draw_text(framebuffer, width, height, shaped_runs.items);

    rl.initWindow(width, height, "Framebuffer");
    defer rl.closeWindow();

    const image: rl.Image = .{
        .data = framebuffer.ptr,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = rl.PixelFormat.uncompressed_r8g8b8a8,
    };

    const texture = try rl.Texture.fromImage(image);

    while (!rl.windowShouldClose()) {
        rl.updateTexture(texture, framebuffer.ptr);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);
        rl.drawTexture(texture, 0, 0, .white);
    }
}

const Pixel = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

fn blend_channel(fg: u8, bg: u8, alpha: u8) u8 {
    const a: u16 = alpha;

    return @intCast((a * fg + (255 - a) * bg) / 255);
}

fn draw_bitmap(
    pixels: []Pixel,
    width: usize,
    height: usize,
    bitmap: ft.FT_Bitmap,
    left: i32,
    top: i32,
    foreground_color: Pixel,
) void {
    for (0..bitmap.rows) |y| {
        const dest_y = @as(usize, @intCast(top)) + y;
        if (dest_y < 0 or dest_y >= height) continue;

        // TODO: should we use bitmap.pitch?
        for (0..bitmap.width) |x| {
            const dest_x = @as(usize, @intCast(left)) + x;
            if (dest_x < 0 or dest_x >= width) continue;

            const coverage = bitmap.buffer[(y * @as(usize, @intCast(bitmap.pitch))) + x];
            if (coverage == 0)
                continue;

            const idx = (dest_y * width) + dest_x;

            const background_color = pixels[idx];
            pixels[idx] = .{
                .r = blend_channel(foreground_color.r, background_color.r, coverage),
                .g = blend_channel(foreground_color.g, background_color.g, coverage),
                .b = blend_channel(foreground_color.b, background_color.b, coverage),
                .a = 255,
            };
        }
    }
}

fn draw_glyph(
    pixels: []Pixel,
    width: usize,
    height: usize,
    face: ft.FT_Face,
    glyph_index: hb.hb_codepoint_t,
    x: hb.hb_position_t,
    y: hb.hb_position_t,
) !void {
    var ft_error: ft.FT_Error = undefined;

    ft_error = ft.FT_Load_Glyph(face, glyph_index, ft.FT_LOAD_DEFAULT | ft.FT_LOAD_NO_HINTING);
    if (ft_error != 0) {
        std.debug.print("Error({}): Failed to load glyph\n", .{ft_error});
        return error.TODO;
    }

    ft_error = ft.FT_Render_Glyph(face.*.glyph, ft.FT_RENDER_MODE_NORMAL);
    if (ft_error != 0) {
        std.debug.print("Error({}): Failed to rneder glyph\n", .{ft_error});
        return error.TODO;
    }

    draw_bitmap(
        pixels,
        width,
        height,
        face.*.glyph.*.bitmap,
        (x >> 6) + face.*.glyph.*.bitmap_left,
        (y >> 6) - face.*.glyph.*.bitmap_top,
        .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    );
}

fn draw_text(
    pixels: []Pixel,
    width: usize,
    height: usize,
    shaped_text: []ShapedRun,
) !void {
    var cursor_x: hb.hb_position_t = 0 << 6;
    var cursor_y: hb.hb_position_t = @intCast(shaped_text[0].font.ft_face.*.size.*.metrics.ascender);

    for (shaped_text) |run| {
        for (0..run.glyph_count) |i| {
            try draw_glyph(
                pixels,
                width,
                height,
                run.font.ft_face,
                run.glyph_info[i].codepoint,
                @intCast(cursor_x + run.glyph_pos[i].x_offset),
                @intCast(cursor_y + run.glyph_pos[i].y_offset),
            );

            cursor_x += run.glyph_pos[i].x_advance;
            cursor_y += run.glyph_pos[i].y_advance;
        }

        // cursor_x = 0 << 6;
        // cursor_y += @intCast(run.font.ft_face.*.size.*.metrics.height);
    }
}

const ShapedRun = struct {
    run: *Item, // source itemization run (it is not owned)
    buf: ?*hb.hb_buffer_t, // keep alive — glyph arrays point into it
    glyph_info: [*c]hb.hb_glyph_info_t,
    glyph_pos: [*c]hb.hb_glyph_position_t,
    glyph_count: usize,
    font: *Font,

    const Self = @This();

    // TODO: Handle errors
    fn init(text: []const u8, item: *Item, font_mgr: *FontMgr) !Self {
        const buf = hb.hb_buffer_create();
        hb.hb_buffer_add_utf8(buf, text.ptr, @intCast(text.len), @intCast(item.start), @intCast(item.length));
        hb.hb_buffer_set_direction(buf, if (item.is_rtl()) hb.HB_DIRECTION_RTL else hb.HB_DIRECTION_LTR);

        hb.hb_buffer_set_script(buf, hb.hb_script_from_string(icu.uscript_getShortName(item.script), -1));

        // TODO: Move this into itemization
        const font = try font_mgr.select_font(text[item.start..(item.start + item.length)]);

        hb.hb_shape(font.hb_font, buf, null, 0);

        var glyph_count: c_uint = undefined;
        const glyph_info = hb.hb_buffer_get_glyph_infos(buf, &glyph_count);
        const glyph_pos = hb.hb_buffer_get_glyph_positions(buf, &glyph_count);

        return .{
            .run = item,
            .buf = buf,
            .glyph_info = glyph_info,
            .glyph_pos = glyph_pos,
            .glyph_count = glyph_count,
            .font = font,
        };
    }

    fn deinit(self: *Self) void {
        hb.hb_buffer_destroy(self.buf);
    }
};

const Font = struct {
    ft_face: ft.FT_Face,
    hb_font: *hb.hb_font_t,
};

const FontMgr = struct {
    library: ft.FT_Library,
    font_list: std.ArrayList(Font),
    allocator: std.mem.Allocator,

    const Self = @This();

    fn init(allocator: std.mem.Allocator) !Self {
        var library: ft.FT_Library = undefined;

        if (ft.FT_Init_FreeType(&library) != 0) {
            return error.FreeTypeFailed;
        }

        return .{
            .allocator = allocator,
            .library = library,
            .font_list = .empty,
        };
    }

    fn deinit(self: *Self) void {
        for (self.font_list.items) |font| {
            hb.hb_font_destroy(font.hb_font);
            _ = ft.FT_Done_Face(font.ft_face);
        }

        self.font_list.deinit(self.allocator);
        _ = ft.FT_Done_FreeType(self.library);
    }

    fn load_font(self: *Self, path: [:0]const u8, font_size: ft.FT_UInt) !void {
        var ft_face: ft.FT_Face = undefined;
        if (ft.FT_New_Face(self.library, path, 0, &ft_face) != 0) {
            return error.FreeTypeFailed;
        }

        if (ft.FT_Set_Pixel_Sizes(ft_face, 0, font_size) != 0) {
            return error.FreeTypeFailed;
        }

        const hb_font = hb.hb_ft_font_create_referenced(@ptrCast(ft_face)) orelse return error.HarbuzzError;

        try self.font_list.append(self.allocator, .{
            .ft_face = ft_face,
            .hb_font = hb_font,
        });
    }

    fn select_font(self: *Self, text: []const u8) !*Font {
        std.debug.assert(self.font_list.items.len > 0);

        for (self.font_list.items) |*font| {
            const face = font.ft_face;

            var covers_all = true;
            const view = try std.unicode.Utf8View.init(text);
            var iter = view.iterator();
            while (iter.nextCodepoint()) |codepoint| {
                // skip spaces/control chars
                if (codepoint <= 0x20) continue;

                if (ft.FT_Get_Char_Index(face, codepoint) == 0) {
                    covers_all = false;
                    break;
                }
            }

            if (covers_all)
                return font;
        }

        // Nothing covers it fully — return last font (usually a fallback like Noto)
        return &self.font_list.items[self.font_list.items.len - 1];
    }
};

pub const ScriptRun = struct {
    start: usize,
    end: usize,
    script: icu.UScriptCode,
};

pub const ScriptRunIterator = struct {
    text: []const u8,
    i: usize,

    const Self = @This();

    fn init(text: []const u8) !Self {
        // TODO: replace invalid characters with replacement character instead of failing.
        if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;

        return .{
            .text = text,
            .i = 0,
        };
    }

    // TODO: implement mechanism to segment emojis here or add emoji run iterator.
    fn next(self: *Self) !?ScriptRun {
        if (self.i >= self.text.len) {
            return null;
        }

        const start = self.i;
        var script = icu.USCRIPT_INVALID_CODE;
        while (self.i < self.text.len) {
            const codepoint_start = self.i;

            const bytes_len = std.unicode.utf8ByteSequenceLength(self.text[self.i]) catch unreachable;
            const codepoint = utf8_decode(self.text[self.i..(self.i + bytes_len)]) catch unreachable;
            self.i += bytes_len;

            var err: icu.UErrorCode = icu.U_ZERO_ERROR;
            const current_script = icu.uscript_getScript(codepoint, &err);
            if (icu.U_FAILURE(err)) return error.IcuError;

            if (current_script == icu.USCRIPT_COMMON or current_script == icu.USCRIPT_INHERITED or current_script == icu.USCRIPT_INVALID_CODE) {
                continue;
            }

            if (script == icu.USCRIPT_INVALID_CODE) {
                script = current_script;
            } else if (current_script != script) {
                self.i = codepoint_start;
                return .{ .start = start, .end = self.i, .script = script };
            }
        }

        // ran off the end, all COMMON/INHERITED
        if (script == icu.USCRIPT_INVALID_CODE) script = icu.USCRIPT_COMMON;
        return .{ .start = start, .end = self.i, .script = script };
    }
};

const BiDi = struct {
    allocator: std.mem.Allocator,
    ubidi: *icu.UBiDi,
    utf16_text: []u16,

    const Self = @This();

    fn init(utf8_text: []const u8, allocator: std.mem.Allocator) !Self {
        const utf16_text = try std.unicode.utf8ToUtf16LeAlloc(allocator, utf8_text);
        errdefer allocator.free(utf16_text);

        const bidi = icu.ubidi_open() orelse return error.IcuOpenFailed;
        errdefer icu.ubidi_close(bidi);

        var error_code: icu.UErrorCode = icu.U_ZERO_ERROR;
        icu.ubidi_setPara(bidi, utf16_text.ptr, @intCast(utf16_text.len), icu.UBIDI_DEFAULT_LTR, null, &error_code);
        if (icu.U_FAILURE(error_code)) {
            return error.IcuParaError;
        }

        return .{
            .ubidi = bidi,
            .allocator = allocator,
            .utf16_text = utf16_text,
        };
    }

    // pub fn visual_runs(self: *Self) !BiDiRunIterator {
    //     return BiDiRunIterator.init(self);
    // }
    pub fn visual_runs(self: *Self) !BiDiLevelIterator {
        return BiDiLevelIterator.init(self, self.utf16_text.len);
    }

    fn deinit(self: *Self) void {
        icu.ubidi_close(self.ubidi);
        self.allocator.free(self.utf16_text);
    }
};

pub const BiDiRun = struct {
    level: icu.UBiDiLevel,
    start: usize,
    end: usize,
};

pub const BiDiLevelIterator = struct {
    bidi: *BiDi,
    text_len: usize,
    index: usize,

    pub fn init(bidi: *BiDi, text_len: usize) BiDiLevelIterator {
        _ = text_len;
        return .{ .bidi = bidi, .text_len = bidi.utf16_text.len, .index = 0 };
    }

    pub fn next(self: *BiDiLevelIterator) ?BiDiRun {
        if (self.index >= self.text_len) return null;

        var limit: i32 = undefined;
        var level: icu.UBiDiLevel = undefined;
        icu.ubidi_getLogicalRun(self.bidi.ubidi, @intCast(self.index), &limit, &level);

        const start = self.index;
        self.index = @intCast(limit);

        const byte_start = utf16_index_to_utf8(self.bidi.utf16_text, @intCast(start));
        const byte_end = utf16_index_to_utf8(self.bidi.utf16_text, @intCast(self.index));

        return .{ .start = @intCast(byte_start), .end = @intCast(byte_end), .level = level };
    }
};

// pub const BiDiRun = struct {
//     direction: icu.UBiDiDirection,
//     start: i32,
//     length: i32,
// };

// pub const BiDiRunIterator = struct {
//     bidi: *BiDi,
//     run_count: i32,
//     index: i32 = 0,

//     pub fn init(bidi: *BiDi) !BiDiRunIterator {
//         var err: icu.UErrorCode = icu.U_ZERO_ERROR;
//         const count = icu.ubidi_countRuns(bidi.ubidi, &err);
//         if (icu.U_FAILURE(err)) return error.IcuError;

//         return .{ .bidi = bidi, .run_count = count };
//     }

//     pub fn next(self: *BiDiRunIterator) ?BiDiRun {
//         if (self.index >= self.run_count) {
//             return null;
//         }

//         var start: i32 = undefined;
//         var length: i32 = undefined;

//         const dir = icu.ubidi_getVisualRun(self.bidi.ubidi, self.index, &start, &length);

//         const byte_start = utf16_index_to_utf8(self.bidi.utf16_text, start);
//         const byte_end = utf16_index_to_utf8(self.bidi.utf16_text, start + length);

//         self.index += 1;
//         return .{ .direction = dir, .start = byte_start, .length = byte_end - byte_start };
//     }
// };

fn utf16_index_to_utf8(utf16: []const u16, utf16_index: i32) i32 {
    var err: icu.UErrorCode = icu.U_ZERO_ERROR;
    var utf8_offset: i32 = 0;

    // passing only the prefix [0, utf16_index) — destLength becomes its UTF-8 length
    _ = icu.u_strToUTF8(null, 0, &utf8_offset, utf16.ptr, utf16_index, &err);
    std.debug.assert(err == icu.U_BUFFER_OVERFLOW_ERROR or err == icu.U_STRING_NOT_TERMINATED_WARNING);
    // U_BUFFER_OVERFLOW_ERROR is expected and fine here

    return utf8_offset;
}

fn utf8_decode(bytes: []const u8) !u21 {
    return switch (bytes.len) {
        1 => bytes[0],
        2 => std.unicode.utf8Decode2(bytes[0..2].*),
        3 => std.unicode.utf8Decode3(bytes[0..3].*),
        4 => std.unicode.utf8Decode4(bytes[0..4].*),
        else => unreachable,
    };
}

const BidiCursor = struct {
    iter: BiDiLevelIterator,
    current: ?BiDiRun,

    const Self = @This();

    fn init(iter: BiDiLevelIterator) Self {
        var self = Self{ .iter = iter, .current = null };
        self.current = self.iter.next();

        return self;
    }

    fn end(self: Self, text_len: usize) usize {
        return if (self.current) |r| r.end else text_len;
    }

    fn level(self: Self) icu.UBiDiLevel {
        return if (self.current) |r| r.level else 0;
    }

    fn advance(self: *Self) void {
        self.current = self.iter.next();
    }
};

const ScriptCursor = struct {
    iter: ScriptRunIterator,
    current: ?ScriptRun,

    const Self = @This();

    fn init(iter: ScriptRunIterator) !Self {
        var self = Self{ .iter = iter, .current = null };
        self.current = try self.iter.next();

        return self;
    }

    fn end(self: Self, text_len: usize) usize {
        return if (self.current) |r| r.end else text_len;
    }

    fn script(self: Self) icu.UScriptCode {
        return if (self.current) |r| r.script else icu.USCRIPT_COMMON;
    }

    fn advance(self: *Self) !void {
        self.current = try self.iter.next();
    }
};

pub const Item = struct {
    start: usize,
    length: usize,
    level: icu.UBiDiLevel,
    script: icu.UScriptCode,

    pub fn is_rtl(self: Item) bool {
        return self.level % 2 == 1;
    }
};

// TODO: should I use utf-16 in itemizer to simplify code of BiDi.
pub const Itemizer = struct {
    text: []const u8,
    pos: usize = 0,
    bidi_cursor: BidiCursor,
    script_cursor: ScriptCursor,

    pub fn init(bidi: *BiDi, text: []const u8) !Itemizer {
        return .{
            .text = text,
            .bidi_cursor = BidiCursor.init(BiDiLevelIterator.init(bidi, text.len)),
            .script_cursor = try ScriptCursor.init(try ScriptRunIterator.init(text)),
        };
    }

    pub fn next(self: *Itemizer) !?Item {
        if (self.pos >= self.text.len) return null;

        const bidi_end = self.bidi_cursor.end(self.text.len);
        const script_end = self.script_cursor.end(self.text.len);
        const end = @min(bidi_end, script_end);

        const item = Item{
            .start = self.pos,
            .length = end - self.pos,
            .level = self.bidi_cursor.level(),
            .script = self.script_cursor.script(),
        };

        if (end == bidi_end) self.bidi_cursor.advance();
        if (end == script_end) try self.script_cursor.advance();
        self.pos = end;

        return item;
    }
};
