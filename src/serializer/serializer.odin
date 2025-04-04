
package serializer
///////////////////////////////////////////////////////////////////////////////////////////////////////////
// LBP Serializer
//
// Explanation of the method:
// https://handmade.network/p/29/swedish-cubes-for-unity/blog/p/2723-how_media_molecule_does_serialization
//
// Note: numbers are automatically converted to little endian, and pointer-sized
// types are always treated as 64-bit. see `serialize_number` for more information.
//
// TODO:
// - handle endianness better: now only integers and floats are hardcoded. Enums and bit_sets aren't.

// Credit: https://github.com/jakubtomsu/odin-lbp-serialization/blob/main/serializer.odin

import "core:fmt"
import "base:intrinsics"
import "core:mem"
import "base:runtime"
import "core:slice"
import sa "core:container/small_array"

_ :: fmt // fmt is used only for debug printing

SERIALIZER_ENABLE_GENERIC :: #config(SERIALIZER_ENABLE_GENERIC, true)

// Each update to the data layout should be a value in this enum.
// WARNING: do not change the order of these!
Serializer_Version :: enum u32le {
    initial = 0,
    add_foo_delta = 1,
    add_foo_epsilon = 2,
    add_foo_gamma = 3,
    add_foo_zeta = 4,
    rem_foo_epsilon = 5,
    mod_foo_zeta_f32_to_array = 6,
    add_bar_and_move_foo_into_collection = 7,
    // Don't remove this!
    LATEST_PLUS_ONE,
}

SERIALIZER_VERSION_LATEST :: Serializer_Version(int(Serializer_Version.LATEST_PLUS_ONE) - 1)

Serializer :: struct {
    is_writing:  bool,
    data:        [dynamic]byte,
    read_offset: int,
    version:     Serializer_Version,
    debug:       Serializer_Debug,
}

when ODIN_DEBUG {
    Serializer_Debug :: struct {
        print_scope: bool,
        depth:       int,
    }
} else {
    Serializer_Debug :: struct {}
}

serializer_init_writer :: proc(
    s: ^Serializer,
    capacity: int = 1024,
    allocator := context.allocator,
    loc := #caller_location,
) -> mem.Allocator_Error {
    s^ = {
        is_writing = true,
        version    = SERIALIZER_VERSION_LATEST,
        data       = make([dynamic]byte, 0, capacity, allocator, loc) or_return,
    }
    return nil
}

// Warning: doesn't clone the data, make sure it stays available when deserializing!
serializer_init_reader :: proc(s: ^Serializer, data: []byte) {
    s^ = {
        is_writing = false,
        data       = transmute([dynamic]u8)runtime.Raw_Dynamic_Array{
            data = (transmute(runtime.Raw_Slice)data).data,
            len = len(data),
            cap = len(data),
            allocator = runtime.nil_allocator(),
        },
    }
}

serializer_clear :: proc(s: ^Serializer) {
    s.read_offset = 0
    clear(&s.data)
}

// The reader doesn't need to be destroyed, since it doesn't own the memory
serializer_destroy_writer :: proc(s: ^Serializer, loc := #caller_location) {
    assert(s.is_writing)
    delete(s.data, loc)
}

serializer_data :: proc(s: Serializer) -> []u8 {
    return s.data[:]
}

_serializer_debug_scope_indent :: proc(depth: int) {
    for _ in 0 ..< depth {
        runtime.print_string("  ")
    }
}

_serializer_debug_scope_end :: proc(s: ^Serializer, name: string) {
    when ODIN_DEBUG do if s.debug.print_scope {
        s.debug.depth -= 1
        _serializer_debug_scope_indent(s.debug.depth)
        runtime.print_string("}\n")
    }
}

@(disabled = !ODIN_DEBUG, deferred_in = _serializer_debug_scope_end)
serializer_debug_scope :: proc(s: ^Serializer, name: string) {
    when ODIN_DEBUG do if s.debug.print_scope {
        _serializer_debug_scope_indent(s.debug.depth)
        runtime.print_string(name)
        runtime.print_string(" {")
        runtime.print_string("\n")
        s.debug.depth += 1
    }
}

@(require_results, optimization_mode = "favor_size")
_serialize_bytes :: proc(s: ^Serializer, data: []byte, loc: runtime.Source_Code_Location) -> bool {
    when ODIN_DEBUG do if s.debug.print_scope {
        _serializer_debug_scope_indent(s.debug.depth)
        fmt.printf("%i bytes, ", len(data))
        if s.is_writing {
            fmt.printf("written: %i\n", len(s.data))
        } else {
            fmt.printf("read: %i/%i\n", s.read_offset, len(s.data))
        }
    }

    if len(data) == 0 {
        return true
    }

    if s.is_writing {
        if _, err := append(&s.data, ..data); err != nil {
            when ODIN_DEBUG {
                panic("Serializer failed to append data", loc)
            }
            return false
        }
    } else {
        if len(s.data) < s.read_offset + len(data) {
            when ODIN_DEBUG {
                panic("Serializer attempted to read past the end of the buffer.", loc)
            }
            return false
        }
        copy(data, s.data[s.read_offset:][:len(data)])
        s.read_offset += len(data)
    }

    return true
}

serialize_opaque :: #force_inline proc(s: ^Serializer, data: ^$T, loc := #caller_location) -> bool {
    return _serialize_bytes(s, #force_inline mem.ptr_to_bytes(data), loc)
}

// Serialize slice, fields are treated as opaque bytes.
serialize_opaque_slice :: proc(s: ^Serializer, data: ^$T/[]$E, loc := #caller_location) -> bool {
    serializer_debug_scope(s, "opaque slice")
    serialize_slice_info(s, data, loc) or_return
    return _serialize_bytes(s, slice.to_bytes(data^), loc)
}

// Serialize dynamic array, but leaves fields empty.
serialize_slice_info :: proc(s: ^Serializer, data: ^$T/[]$E, loc := #caller_location) -> bool {
    serializer_debug_scope(s, "slice info")
    num_items := len(data)
    serialize_number(s, &num_items, loc) or_return
    if !s.is_writing {
        data^ = make([]E, num_items, loc = loc)
    }
    return true
}

// Serialize dynamic array, but leaves fields empty.
serialize_dynamic_array_info :: proc(
    s: ^Serializer,
    data: ^$T/[dynamic]$E,
    loc := #caller_location,
) -> bool {
    serializer_debug_scope(s, "dynamic array info")
    num_items := len(data)
    serialize_number(s, &num_items, loc) or_return
    if !s.is_writing {
        data^ = make([dynamic]E, num_items, num_items, loc = loc)
    }
    return true
}

// Serialize dynamic array, fields are treated as opaque bytes.
serialize_opaque_dynamic_array :: proc(
    s: ^Serializer,
    data: ^$T/[dynamic]$E,
    loc := #caller_location,
) -> bool {
    serializer_debug_scope(s, "opaque dynamic array")
    serialize_dynamic_array_info(s, data, loc) or_return
    return _serialize_bytes(s, slice.to_bytes(data[:]), loc)
}

serialize_opaque_as :: proc(s: ^Serializer, data: ^$T, $CONVERT_T: typeid, loc := #caller_location) -> bool {
    serializer_debug_scope(s, fmt.tprint(typeid_of(T), "as", typeid_of(CONVERT_T)))
    if s.is_writing {
        d := CONVERT_T(data^)
        serialize_opaque(s, &d, loc) or_return
    } else {
        d: CONVERT_T
        serialize_opaque(s, &d, loc) or_return
        data^ = T(d)
    }
    return true
}

// Automatically converts to little endian
serialize_number :: proc(
    s: ^Serializer,
    data: ^$T,
    loc := #caller_location,
) -> bool where intrinsics.type_is_float(T) || intrinsics.type_is_integer(T) {
    serializer_debug_scope(s, fmt.tprint(typeid_of(T), "=", data^))

    // Always
    when ODIN_ENDIAN != .Big {
        // Serialize pointer-sized integers as 64-bit
        switch typeid_of(T) {
        case int:
            return serialize_opaque_as(s, data, i64, loc)
        case uint:
            return serialize_opaque_as(s, data, i64, loc)
        case uintptr:
            return serialize_opaque_as(s, data, i64, loc)
        case:
            return serialize_opaque(s, data, loc)
        }

    } else {
        
            // odinfmt: disable
        switch typeid_of(T) {
        case int: return serialize_opaque_as(s, data, i64le, loc)
        case i16: return serialize_opaque_as(s, data, i16le, loc)
        case i32: return serialize_opaque_as(s, data, i32le, loc)
        case i64: return serialize_opaque_as(s, data, i64le, loc)
        case i128: return serialize_opaque_as(s, data, i128le, loc)

        case uint: return serialize_opaque_as(s, data, u64le, loc)
        case u16: return serialize_opaque_as(s, data, u16le, loc)
        case u32: return serialize_opaque_as(s, data, u32le, loc)
        case u64: return serialize_opaque_as(s, data, u64le, loc)
        case u128: return serialize_opaque_as(s, data, u128le, loc)
        case uintptr: return serialize_opaque_as(s, data, u64le, loc)

        case f16: return serialize_opaque_as(s, data, f16le, loc)
        case f32: return serialize_opaque_as(s, data, f32le, loc)
        case f64: return serialize_opaque_as(s, data, f64le, loc)
        
        case:
            return serialize_opaque(s, data, loc)
        }
        // odinfmt: enable
    }

    if !s.is_writing {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T), "=", data^))
    }

    return false
}


serialize_basic :: proc(
    s: ^Serializer,
    data: ^$T,
    loc := #caller_location,
) -> bool where intrinsics.type_is_enum(T) ||
    intrinsics.type_is_boolean(T) ||
    intrinsics.type_is_bit_set(T) {
    serializer_debug_scope(s, fmt.tprint(typeid_of(T), "=", data^))
    return serialize_opaque(s, data, loc)
}


when SERIALIZER_ENABLE_GENERIC {
    serialize_array :: proc(s: ^Serializer, data: ^$T/[$S]$E, loc := #caller_location) -> bool {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
        when intrinsics.type_is_numeric(E) {
            serialize_opaque(s, data, loc) or_return
        } else {
            for &v in data {
                serialize(s, &v, loc) or_return
            }
        }
        return true
    }


    serialize_slice :: proc(s: ^Serializer, data: ^$T/[]$E, loc := #caller_location) -> bool {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
        serialize_slice_info(s, data, loc) or_return
        for &v in data {
            serialize(s, &v, loc) or_return
        }
        return true
    }


    serialize_string :: proc(s: ^Serializer, data: ^string, loc := #caller_location) -> bool {
        serializer_debug_scope(s, fmt.tprintf("string = \"%s\"", data^))
        return serialize_opaque_slice(s, transmute(^[]u8)data, loc)
    }


    serialize_dynamic_array :: proc(s: ^Serializer, data: ^$T/[dynamic]$E, loc := #caller_location) -> bool {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
        serialize_dynamic_array_info(s, data, loc) or_return
        for &v in data {
            serialize(s, &v, loc) or_return
        }
        return true
    }

    serialize_small_array :: proc(s: ^Serializer, a: ^$A/sa.Small_Array($N, $T), loc := #caller_location) -> bool {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
        serialize(s, &a.len, loc) or_return
        for &v in a.data {
            serialize(s, &v, loc) or_return
        }
        return true
    }


    serialize_map :: proc(s: ^Serializer, data: ^$T/map[$K]$V, loc := #caller_location) -> bool {
        serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
        num_items := len(data)
        serialize_number(s, &num_items, loc) or_return

        if s.is_writing {
            for k, v in data {
                k_ := k
                v_ := v
                serialize(s, &k_, loc) or_return
                when size_of(V) > 0 {
                    serialize(s, &v_, loc) or_return
                }
            }
        } else {
            data^ = make_map(map[K]V, num_items)
            for _ in 0 ..< num_items {
                k: K
                v: V
                serialize(s, &k, loc) or_return
                when size_of(V) > 0 {
                    serialize(s, &v, loc) or_return
                }
                data[k] = v
            }
        }

        return true
    }
}

// WARNING: this requires RTTI!
serialize_union_tag :: proc(
    s: ^Serializer,
    value: ^$T,
    loc := #caller_location,
) -> bool where intrinsics.type_is_union(T) {
    serializer_debug_scope(s, "union tag")
    tag: i64le
    if s.is_writing {
        tag = reflect.get_union_variant_raw_tag(value^)
    }
    serialize_basic(s, &tag, loc) or_return
    if !s.is_writing {
        reflect.set_union_variant_raw_tag(value^, tag)
    }
    return true
}


when SERIALIZER_ENABLE_GENERIC {
    serialize :: proc {
        serialize_number,
        serialize_basic,
        serialize_array,
        serialize_slice,
        serialize_string,
        serialize_dynamic_array,
        serialize_map,

        // Everything below this comment is for example purposes.
        // The above code can be copied and used within your own project
        // The below code demonstrates how versioning logic would work
        serialize_foo,
        serialize_bar,
        serialize_collection,
    }
}

Foo :: struct {
    alpha: f32,
    beta: f32,
    chi: f32,
    delta: f32,
    gamma: f32,
    zeta: [16]f32,
}

Bar :: struct {
    kappa: i32,
    mu: i32,
}

Collection :: struct {
    foo: Foo,
    bar: Bar,
}

serialize_collection :: proc(s: ^Serializer, collection: ^Collection, loc := #caller_location) -> bool {
    if s.is_writing {
        s.version = SERIALIZER_VERSION_LATEST
    }

    serialize(s, &s.version, loc) or_return

    if !s.is_writing && s.version > SERIALIZER_VERSION_LATEST {
        fmt.printf("Unsupported version: %d\n", s.version);
        return false;
    }

    if s.version >= .add_bar_and_move_foo_into_collection {
        serialize(s, &collection.foo, loc) or_return
        serialize(s, &collection.bar, loc) or_return
    } else {
        // Collection did not exist yet.
        // The data file will just contain a `Foo`
        // as that was what was originally being saved to the file before
        // `Collection` was added with `Foo` as its field`

        // need to set back to 0 because Foo will read the version again
        s.read_offset = 0
        foo: Foo
        serialize(s, &foo, loc) or_return

        default_bar := Bar {300, 301}

        collection.foo = foo
        collection.bar = default_bar

        // can return now because collection never existed yet
        return true
    }


    return true
}

serialize_bar :: proc(s: ^Serializer, bar: ^Bar, loc := #caller_location) -> bool{
    if s.is_writing {
        s.version = SERIALIZER_VERSION_LATEST
    }

    serialize(s, &s.version, loc) or_return

    if !s.is_writing && s.version > SERIALIZER_VERSION_LATEST {
        fmt.printf("Unsupported version: %d\n", s.version);
        return false;
    }

    if s.version >= .add_bar_and_move_foo_into_collection {
        // these are the initial fields in the first version that collection is created
        serialize(s, &bar.kappa, loc) or_return
        serialize(s, &bar.mu, loc) or_return
    }

    return true
}

serialize_foo :: proc(s: ^Serializer, foo: ^Foo, loc := #caller_location) -> bool {
    if s.is_writing {
        s.version = SERIALIZER_VERSION_LATEST
    }

    serialize(s, &s.version, loc) or_return

    if !s.is_writing && s.version > SERIALIZER_VERSION_LATEST {
        fmt.printf("Unsupported version: %d\n", s.version);
        return false;
    }

    serialize(s, &foo.alpha, loc) or_return
    serialize(s, &foo.beta, loc) or_return
    serialize(s, &foo.chi, loc) or_return
    if s.version >= .add_foo_delta {
        serialize(s, &foo.delta, loc) or_return
    } else {
        default_delta_for_some_reason : f32 = 100
        foo.delta = default_delta_for_some_reason
    }

    // OLD
    // if s.version >= .add_foo_epsilon {
    //     serialize(s, &foo.epsilon, loc) or_return
    // } else {
    //     default_epsilon_for_some_reason : f32 = 200
    //     foo.epsilon = default_epsilon_for_some_reason
    // }

    // need to account for versions that existed before the addition of the field too
    // so we must check the range of versions where this field was present
    if s.version >= .add_foo_epsilon &&  s.version < .rem_foo_epsilon {
        epsilon : f32
        serialize(s, &epsilon, loc) or_return
        // demonstrating a situation where another field would be modified based on some value of an older (now removed) field
        foo.delta += epsilon
    }

    if s.version >= .add_foo_gamma {
        serialize(s, &foo.gamma, loc) or_return
    } else {
        default_gamma_for_some_reason : f32 = 300
        foo.gamma = default_gamma_for_some_reason
    }

    // OLD
    // if s.version >= .add_foo_zeta {
    //     serialize(s, &foo.zeta, loc) or_return
    // } else {
    //     default_zeta_for_some_reason : f32 = 400
    //     foo.zeta = default_zeta_for_some_reason
    // }

    if s.version >= .mod_foo_zeta_f32_to_array {
        serialize(s, &foo.zeta, loc) or_return
    } else if s.version >= .add_foo_zeta {
        // this is a version after zeta was added, but before the type change modification
        zeta_single_value: f32
        serialize(s, &zeta_single_value) or_return
        foo.zeta[0] = zeta_single_value
    } else {
        // this version was before the zeta field was ever added to begin with
        default_zeta_for_some_reason := [16]f32{1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0}
        foo.zeta = default_zeta_for_some_reason
    }


    return true
}
