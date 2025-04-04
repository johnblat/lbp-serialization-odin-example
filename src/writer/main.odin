package writer

import "core:fmt"
import "core:os/os2"
import ser "../serializer"

main :: proc() {

    foo := ser.Foo{5, 5, 5}

    serializer_writer: ser.Serializer
    allocation_err := ser.serializer_init_writer(&serializer_writer)
    if allocation_err != .None {
        fmt.printfln("%v", allocation_err)
    }
    else {
        ok := ser.serialize(&serializer_writer, &foo)
        if ok {
            os_err := os2.write_entire_file("data", serializer_writer.data[:])
            if os_err != nil {
                fmt.printfln("%v", os_err)
            }
        }
        ser.serializer_destroy_writer(&serializer_writer)
    }
}