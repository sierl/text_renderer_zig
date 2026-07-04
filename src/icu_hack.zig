const std = @import("std");
const icu = @import("icu");

const icu_version_suffix = icu.U_ICU_VERSION_MAJOR_NUM;

fn get_icu_fn(
    comptime name: []const u8,
    comptime version: comptime_int,
) @TypeOf(@field(icu, std.fmt.comptimePrint("{s}_{}", .{ name, version }))) {
    return @field(
        icu,
        std.fmt.comptimePrint("{s}_{}", .{ name, version }),
    );
}

// Types
pub const UErrorCode = icu.UErrorCode;

pub const UScriptCode = icu.UScriptCode;

pub const UBiDi = icu.UBiDi;
pub const UBiDiLevel = icu.UBiDiLevel;

// Constants
pub const U_ZERO_ERROR = icu.U_ZERO_ERROR;
pub const U_FAILURE = icu.U_FAILURE;
pub const U_BUFFER_OVERFLOW_ERROR = icu.U_BUFFER_OVERFLOW_ERROR;
pub const U_STRING_NOT_TERMINATED_WARNING = icu.U_STRING_NOT_TERMINATED_WARNING;

pub const UBIDI_DEFAULT_LTR = icu.UBIDI_DEFAULT_LTR;

pub const USCRIPT_INVALID_CODE = icu.USCRIPT_INVALID_CODE;
pub const USCRIPT_COMMON = icu.USCRIPT_COMMON;
pub const USCRIPT_INHERITED = icu.USCRIPT_INHERITED;

// Functions
// The following line expands to:
//     pub const u_strToUTF8 = icu.u_strToUTF8_76;
pub const u_strToUTF8 = get_icu_fn("u_strToUTF8", icu_version_suffix);

pub const uscript_getScript = get_icu_fn("uscript_getScript", icu_version_suffix);
pub const uscript_getShortName = get_icu_fn("uscript_getShortName", icu_version_suffix);

pub const ubidi_open = get_icu_fn("ubidi_open", icu_version_suffix);
pub const ubidi_setPara = get_icu_fn("ubidi_setPara", icu_version_suffix);
pub const ubidi_close = get_icu_fn("ubidi_close", icu_version_suffix);
pub const ubidi_getLogicalRun = get_icu_fn("ubidi_getLogicalRun", icu_version_suffix);
