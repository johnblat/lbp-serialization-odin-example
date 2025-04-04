package reader

import "core:fmt"
import "core:os/os2"
import ser "../serializer"

main :: proc() {

    collection: ser.Collection

    // this program is short lived, but I think the data buffer should
    // probably be either a scratch buffer (it hangs around but is always used for this purpose)
    // or be deleted after its use in a real app
    data, os_err := os2.read_entire_file_from_path("data", context.allocator)
    if os_err != nil {
        fmt.printfln("%v", os_err)
    } else {
        serializer_reader: ser.Serializer
        ser.serializer_init_reader(&serializer_reader, data[:])

        ok := ser.serialize(&serializer_reader, &collection)
        if !ok {
            fmt.printfln("serialize read failed")
        }

        fmt.printfln("version: %d (%v) -> %d (%v)", serializer_reader.version, serializer_reader.version, ser.SERIALIZER_VERSION_LATEST, ser.SERIALIZER_VERSION_LATEST)
    }
    fmt.printfln("%v", collection)
}