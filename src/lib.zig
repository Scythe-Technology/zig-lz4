const std = @import("std");

pub const LZ4F_errorCode = usize;

pub extern fn LZ4_versionNumber() c_int;
pub extern fn LZ4_versionString() [*c]const u8;
pub extern fn LZ4_compress_default(src: [*c]const u8, dst: [*c]u8, srcSize: c_int, dstCapacity: c_int) c_int;
pub extern fn LZ4_decompress_safe(src: [*c]const u8, dst: [*c]u8, compressedSize: c_int, dstCapacity: c_int) c_int;
pub extern fn LZ4_compressBound(inputSize: c_int) c_int;
pub extern fn LZ4F_compressBound(srcSize: usize, prefsPtr: [*c]const Frame.Preferences) usize;
pub extern fn LZ4F_isError(code: usize) c_uint;
pub extern fn LZ4F_getErrorName(code: LZ4F_errorCode) [*c]const u8;
pub extern fn LZ4F_createCompressionContext(cctxPtr: [*c]?*Frame.CompressionContext, version: c_uint) LZ4F_errorCode;
pub extern fn LZ4F_freeCompressionContext(cctx: ?*Frame.CompressionContext) LZ4F_errorCode;
pub extern fn LZ4F_compressBegin(cctx: ?*Frame.CompressionContext, dstBuffer: ?*anyopaque, dstCapacity: usize, prefsPtr: [*c]const Frame.Preferences) usize;
pub extern fn LZ4F_compressUpdate(cctx: ?*Frame.CompressionContext, dstBuffer: ?*anyopaque, dstCapacity: usize, srcBuffer: ?*const anyopaque, srcSize: usize, cOptPtr: [*c]const Frame.CompressOptions) usize;
pub extern fn LZ4F_compressEnd(cctx: ?*Frame.CompressionContext, dstBuffer: ?*anyopaque, dstCapacity: usize, cOptPtr: [*c]const Frame.CompressOptions) usize;
pub extern fn LZ4F_createDecompressionContext(dctxPtr: [*c]?*Frame.DecompressionContext, version: c_uint) LZ4F_errorCode;
pub extern fn LZ4F_freeDecompressionContext(dctx: ?*Frame.DecompressionContext) LZ4F_errorCode;
pub extern fn LZ4F_decompress(dctx: ?*Frame.DecompressionContext, dstBuffer: ?*anyopaque, dstSizePtr: [*c]usize, srcBuffer: ?*const anyopaque, srcSizePtr: [*c]usize, dOptPtr: [*c]const Frame.DecompressOptions) usize;

pub const MAX_INPUT_SIZE = 0x7E000000;
pub const MEMORY_USAGE_MAX = 20;

pub fn getVersion() []const u8 {
    return std.mem.span(LZ4_versionString());
}

pub fn getVersionNumber() i32 {
    return @intCast(LZ4_versionNumber());
}

const Allocator = std.mem.Allocator;

pub const Standard = struct {
    const CompressionError = error{
        Failed,
    };

    const DecompressionError = error{
        Failed,
    };

    pub fn compressBound(size: usize) usize {
        return @intCast(LZ4_compressBound(@intCast(size)));
    }

    pub fn compressDefault(src: []const u8, dest: []u8) !usize {
        const compressedSize = LZ4_compress_default(src.ptr, dest.ptr, @intCast(src.len), @intCast(dest.len));
        if (compressedSize == 0)
            return CompressionError.Failed;
        return @intCast(compressedSize);
    }

    pub fn decompressSafe(src: []const u8, dest: []u8) !usize {
        const decompressedSize = LZ4_decompress_safe(src.ptr, dest.ptr, @intCast(src.len), @intCast(dest.len));
        if (decompressedSize < 0) {
            return DecompressionError.Failed;
        }
        return @intCast(decompressedSize);
    }

    pub fn compress(allocator: Allocator, src: []const u8) ![]u8 {
        const destSize = compressBound(src.len);
        const dest = try allocator.alloc(u8, destSize);
        defer allocator.free(dest);
        const compressedSize = try compressDefault(src, dest);
        const result = try allocator.dupe(u8, dest[0..compressedSize]);
        return result;
    }

    pub fn decompress(allocator: Allocator, src: []const u8, szHint: usize) ![]u8 {
        const dest = try allocator.alloc(u8, szHint);
        errdefer allocator.free(dest);
        _ = try decompressSafe(src, dest);
        return dest;
    }
};

pub const Frame = struct {
    pub const Preferences = extern struct {
        frameInfo: FrameInfo = std.mem.zeroes(FrameInfo),
        compressionLevel: c_int = 0,
        autoFlush: c_uint = 0,
        favorDecSpeed: c_uint = 0,
        reserved: [3]c_uint = std.mem.zeroes([3]c_uint),

        pub const FrameInfo = extern struct {
            blockSizeID: c_uint = 0,
            blockMode: c_uint = 0,
            contentChecksumFlag: c_uint = 0,
            frameType: c_uint = 0,
            contentSize: c_ulonglong = 0,
            dictID: c_uint = 0,
            blockChecksumFlag: c_uint = 0,
        };
    };

    pub const CompressOptions = extern struct {
        stableSrc: c_uint = 0,
        reserved: [3]c_uint = std.mem.zeroes([3]c_uint),
    };

    pub const DecompressOptions = extern struct {
        stableDst: c_uint = 0,
        skipChecksums: c_uint = 0,
        reserved1: c_uint = 0,
        reserved0: c_uint = 0,
    };

    pub const CompressionContext = opaque {
        const Self = @This();

        pub fn compressBegin(self: *Self, dstBuffer: [*]u8, dstCapacity: usize, prefsPtr: ?*const Preferences) !usize {
            const res = LZ4F_compressBegin(self, @ptrCast(dstBuffer), dstCapacity, prefsPtr);
            if (LZ4F_isError(res) != 0) {
                try doError(res);
            }
            return res;
        }
        pub fn compressUpdate(self: *Self, dstBuffer: [*]u8, dstCapacity: usize, srcBuffer: [*]const u8, srcSize: usize, cOptionsPtr: ?*const CompressOptions) !usize {
            const res = LZ4F_compressUpdate(self, @ptrCast(dstBuffer), dstCapacity, @ptrCast(srcBuffer), srcSize, cOptionsPtr);
            if (LZ4F_isError(res) != 0) {
                try doError(res);
            }
            return res;
        }

        pub fn compressEnd(self: *Self, dstBuffer: [*]u8, dstCapacity: usize, cOptionsPtr: ?*const CompressOptions) !usize {
            const res = LZ4F_compressEnd(self, @ptrCast(dstBuffer), dstCapacity, cOptionsPtr);
            if (LZ4F_isError(res) != 0) {
                try doError(res);
            }
            return res;
        }

        pub fn init(versionNumber: ?i32) !*Self {
            var ctxPtr: *Self = undefined;
            const res = LZ4F_createCompressionContext(@ptrCast(&ctxPtr), @intCast(versionNumber orelse getVersionNumber()));
            if (res != 0) {
                try Frame.doError(res);
            }
            return ctxPtr;
        }

        pub fn free(self: *Self) void {
            _ = LZ4F_freeCompressionContext(self);
        }
    };

    pub const DecompressionContext = opaque {
        const Self = @This();

        pub fn init(versionNumber: ?i32) !*Self {
            var ctxPtr: *Self = undefined;
            const res = LZ4F_createDecompressionContext(@ptrCast(&ctxPtr), @intCast(versionNumber orelse getVersionNumber()));
            if (res != 0) {
                try Frame.doError(res);
            }
            return ctxPtr;
        }

        pub fn decompress(self: *Self, dstBuffer: [*]u8, dstCapacity: usize, srcBuffer: [*]const u8, srcSize: usize, dOptionsPtr: ?*const DecompressOptions) !usize {
            var srcSizeMutable = srcSize;
            var dstCapacityMutable = dstCapacity;
            const res = LZ4F_decompress(self, @ptrCast(dstBuffer), @ptrCast(&dstCapacityMutable), @ptrCast(srcBuffer), @ptrCast(&srcSizeMutable), dOptionsPtr);
            if (LZ4F_isError(res) != 0) {
                try doError(res);
            }
            return res;
        }

        pub fn free(self: *Self) void {
            _ = LZ4F_freeDecompressionContext(self);
        }
    };

    pub const Error = error{
        Generic,
        MaxBlockSizeInvalid,
        BlockModeInvalid,
        ParameterInvalid,
        CompressionLevelInvalid,
        HeaderVersionWrong,
        BlockChecksumInvalid,
        ReservedFlagSet,
        AllocationFailed,
        SrcSizeTooLarge,
        DstMaxSizeTooSmall,
        FrameHeaderIncomplete,
        FrameTypeUnknown,
        FrameSizeWrong,
        SrcPtrWrong,
        DecompressionFailed,
        HeaderChecksumInvalid,
        ContentChecksumInvalid,
        FrameDecodingAlreadyStarted,
        CompressionStateUninitialized,
        ParameterNull,
        IoWrite,
        IoRead,
        MaxCode,
    };

    pub const BlockSize = enum(c_uint) {
        Default = 0,
        Max64KB = 4,
        Max256KB = 5,
        Max1MB = 6,
        Max4MB = 7,
    };

    pub const BlockMode = enum(c_uint) {
        Linked = 0,
        Independent = 1,
    };

    pub const ContentChecksum = enum(c_uint) {
        Disabled = 0,
        Enabled = 1,
    };

    pub const BlockChecksum = enum(c_uint) {
        Disabled = 0,
        Enabled = 1,
    };

    pub const FrameType = enum(c_uint) {
        Frame = 0,
        SkippableFrame = 1,
    };

    fn doError(result: usize) !void {
        const code: usize = @intCast(-@as(isize, @bitCast(result)) - 1);
        switch (code) {
            0 => return Error.Generic,
            1 => return Error.MaxBlockSizeInvalid,
            2 => return Error.BlockModeInvalid,
            3 => return Error.ParameterInvalid,
            4 => return Error.CompressionLevelInvalid,
            5 => return Error.HeaderVersionWrong,
            6 => return Error.BlockChecksumInvalid,
            7 => return Error.ReservedFlagSet,
            8 => return Error.AllocationFailed,
            9 => return Error.SrcSizeTooLarge,
            10 => return Error.DstMaxSizeTooSmall,
            11 => return Error.FrameHeaderIncomplete,
            12 => return Error.FrameTypeUnknown,
            13 => return Error.FrameSizeWrong,
            14 => return Error.SrcPtrWrong,
            15 => return Error.DecompressionFailed,
            16 => return Error.HeaderChecksumInvalid,
            17 => return Error.ContentChecksumInvalid,
            18 => return Error.FrameDecodingAlreadyStarted,
            19 => return Error.CompressionStateUninitialized,
            20 => return Error.ParameterNull,
            21 => return Error.IoWrite,
            22 => return Error.IoRead,
            23 => return Error.MaxCode,
            else => return Error.Generic,
        }
    }

    pub fn compressBound(size: usize, pref: *const Preferences) usize {
        return LZ4F_compressBound(@intCast(size), pref);
    }
};

const INPUT_CHUNK_SIZE = 64 * 1024;

pub const Encoder = struct {
    allocator: Allocator = undefined,
    ctx: *Frame.CompressionContext = undefined,
    writer: []u8 = undefined,

    level: u32 = 0,
    blockSize: Frame.BlockSize = Frame.BlockSize.Default,
    blockMode: Frame.BlockMode = Frame.BlockMode.Linked,
    contentChecksum: Frame.ContentChecksum = Frame.ContentChecksum.Enabled,
    blockChecksum: Frame.BlockChecksum = Frame.BlockChecksum.Disabled,
    frameType: Frame.FrameType = Frame.FrameType.Frame,
    favorDecSpeed: bool = false,
    autoFlush: bool = false,

    pub fn init(alloc: Allocator) !Encoder {
        const ptr = try Frame.CompressionContext.init(null);
        return .{
            .allocator = alloc,
            .ctx = ptr,
        };
    }

    pub fn deinit(encoder: *Encoder) void {
        encoder.ctx.free();
    }

    pub fn setLevel(encoder: *Encoder, level: u32) *Encoder {
        encoder.level = level;
        return encoder;
    }

    pub fn setBlockSize(encoder: *Encoder, blockSize: Frame.BlockSize) *Encoder {
        encoder.blockSize = blockSize;
        return encoder;
    }

    pub fn setBlockMode(encoder: *Encoder, blockMode: Frame.BlockMode) *Encoder {
        encoder.blockMode = blockMode;
        return encoder;
    }

    pub fn setContentChecksum(encoder: *Encoder, contentChecksum: Frame.ContentChecksum) *Encoder {
        encoder.contentChecksum = contentChecksum;
        return encoder;
    }

    pub fn setBlockChecksum(encoder: *Encoder, blockChecksum: Frame.BlockChecksum) *Encoder {
        encoder.blockChecksum = blockChecksum;
        return encoder;
    }

    pub fn setFrameType(encoder: *Encoder, frameType: Frame.FrameType) *Encoder {
        encoder.frameType = frameType;
        return encoder;
    }

    pub fn setAutoFlush(encoder: *Encoder, autoFlush: bool) *Encoder {
        encoder.autoFlush = if (autoFlush) 1 else 0;
        return encoder;
    }

    pub fn setFavorDecSpeed(encoder: *Encoder, favorDecSpeed: bool) *Encoder {
        encoder.favorDecSpeed = if (favorDecSpeed) 1 else 0;
        return encoder;
    }

    pub fn compressStream(encoder: *Encoder, streamWriter: *std.io.Writer, src: []const u8) !void {
        const pref = Frame.Preferences{
            .compressionLevel = @intCast(encoder.level),
            .frameInfo = .{
                .blockSizeID = @intFromEnum(encoder.blockSize),
                .blockMode = @intFromEnum(encoder.blockMode),
                .contentChecksumFlag = @intFromEnum(encoder.contentChecksum),
                .blockChecksumFlag = @intFromEnum(encoder.blockChecksum),
                .frameType = @intFromEnum(encoder.frameType),
                .dictID = 0,
            },
            .reserved = [3]c_uint{ 0, 0, 0 },
            .autoFlush = if (encoder.autoFlush) 1 else 0,
            .favorDecSpeed = if (encoder.favorDecSpeed) 1 else 0,
        };
        const bound = Frame.compressBound(src.len, &pref);

        const writer = try encoder.allocator.alloc(u8, bound);
        defer encoder.allocator.free(writer);

        const startRes = try encoder.ctx.compressBegin(writer.ptr, bound, &pref);
        try streamWriter.writeAll(writer[0..startRes]);

        var offset: usize = 0;
        while (offset < src.len) {
            const readSize = @min(src.len - offset, INPUT_CHUNK_SIZE);
            const updateLen = try encoder.ctx.compressUpdate(writer.ptr, bound, src[offset..].ptr, readSize, null);
            if (updateLen == 0)
                break;
            try streamWriter.writeAll(writer[0..updateLen]);
            offset += readSize;
        }

        const endRes = try encoder.ctx.compressEnd(writer.ptr, bound, null);
        try streamWriter.writeAll(writer[0..endRes]);
    }

    pub fn compress(encoder: *Encoder, src: []const u8) ![]const u8 {
        const allocator = encoder.allocator;

        var allocating: std.Io.Writer.Allocating = .init(allocator);
        const writer = &allocating.writer;

        try encoder.compressStream(writer, src);

        try writer.flush();

        return try allocating.toOwnedSlice();
    }
};

pub const Decoder = struct {
    allocator: Allocator = undefined,
    ctx: *Frame.DecompressionContext = undefined,

    const Self = @This();

    pub fn init(alloc: Allocator) !Self {
        const ptr = try Frame.DecompressionContext.init(null);
        return .{
            .allocator = alloc,
            .ctx = ptr,
        };
    }

    pub fn deinit(self: *Self) void {
        self.ctx.free();
    }

    pub fn decompress(self: *Self, src: []const u8, dstSize: usize) ![]const u8 {
        const dest = try self.allocator.alloc(u8, dstSize);
        errdefer self.allocator.free(dest);
        const srcLen = src.len;

        var dstOffset: usize = 0;
        var srcOffset: usize = 0;
        while (dstOffset < dstSize and srcOffset < srcLen) {
            const readSrcSize = srcLen - srcOffset;
            const incrDstSize = dstSize - dstOffset;
            const updateLen = try self.ctx.decompress(dest[dstOffset..].ptr, dstSize, src[srcOffset..].ptr, readSrcSize, null);
            if (updateLen == 0)
                break;
            dstOffset += incrDstSize;
            srcOffset += readSrcSize;
        }

        return dest;
    }
};

const testing = std.testing;
test "version" {
    try testing.expectEqual(10904, getVersionNumber());
    try testing.expectEqualStrings("1.9.4", getVersion());
}

test "frame compression & decompression 112k sample" {
    const allocator = testing.allocator;
    const sampleText = try std.fs.cwd().readFileAlloc(allocator, "./files/112k-sample.txt", std.math.maxInt(usize));
    defer allocator.free(sampleText);

    // Compression
    var encoder = try Encoder.init(allocator);
    _ = encoder.setLevel(0)
        .setContentChecksum(Frame.ContentChecksum.Enabled)
        .setBlockMode(Frame.BlockMode.Independent);
    defer encoder.deinit();

    const compressed = try encoder.compress(sampleText);
    defer allocator.free(compressed);

    const expectedCompressed = try std.fs.cwd().readFileAlloc(allocator, "./files/112k-compressed-expected.txt", std.math.maxInt(usize));
    defer allocator.free(expectedCompressed);
    try testing.expectEqualStrings(expectedCompressed, compressed);

    // Decompression
    var decoder = try Decoder.init(allocator);
    defer decoder.deinit();

    const decompressed = try decoder.decompress(compressed, sampleText.len);
    defer allocator.free(decompressed);
    try testing.expectEqualStrings(sampleText, decompressed);
}

test "frame compression & decompression 1k sample" {
    const allocator = testing.allocator;
    const sampleText = try std.fs.cwd().readFileAlloc(allocator, "./files/1k-sample.txt", std.math.maxInt(usize));
    defer allocator.free(sampleText);

    // Compression
    var encoder = try Encoder.init(allocator);
    _ = encoder.setLevel(0)
        .setContentChecksum(Frame.ContentChecksum.Enabled)
        .setBlockMode(Frame.BlockMode.Independent);
    defer encoder.deinit();

    const compressed = try encoder.compress(sampleText);
    defer allocator.free(compressed);

    const expectedCompressed = try std.fs.cwd().readFileAlloc(allocator, "./files/1k-compressed-expected.txt", std.math.maxInt(usize));
    defer allocator.free(expectedCompressed);
    try testing.expectEqualStrings(expectedCompressed, compressed);

    // Decompression
    var decoder = try Decoder.init(allocator);
    defer decoder.deinit();

    const decompressed = try decoder.decompress(compressed, sampleText.len);
    defer allocator.free(decompressed);
    try testing.expectEqualStrings(sampleText, decompressed);
}

test "standard compression & decompression" {
    const allocator = testing.allocator;
    const sample = "\nLorem ipsum dolor sit amet, consectetur adipiscing elit";

    // Compression
    const compressed = try Standard.compress(allocator, sample);
    defer allocator.free(compressed);

    const expectedCompressed = try std.fs.cwd().readFileAlloc(allocator, "./files/basic-compressed-expected.txt", std.math.maxInt(usize));
    defer allocator.free(expectedCompressed);

    try testing.expectEqualStrings(expectedCompressed, compressed);

    // Decompression
    const decompressed = try Standard.decompress(allocator, compressed, sample.len);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(sample, decompressed);
}
