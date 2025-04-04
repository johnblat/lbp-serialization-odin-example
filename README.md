Using https://github.com/jakubtomsu/odin-lbp-serialization/blob/main/serializer.odin, I created an example and made some modifications to support the latest odin compiler

Using the `src/reader` and `src/writer` programs included in this repo, and custom serialization code in `src/serializer/serializer.odin`, I was able to demo the following things:
- adding fields to a struct
- removing fields from a struct
- converting field types
- moving a saved struct to a container struct
  - Foo moves to Collection.Foo
  - This is cool cause it shows how a rearraging structs might be versioned
 - Attempting to read from a "future version" in an "older version" of the reader app gets an error

You can look at the commit history of the `src/serializer/serializer.odin` file to see a brief example of things changing over time.
