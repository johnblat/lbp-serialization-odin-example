Based off of https://github.com/jakubtomsu/odin-lbp-serialization/blob/main/serializer.odin, I created an example and made some modifications to support the latest odin compiler.

What's in this repo:
- `src/reader`: a program that will read the `data` file and print its contents, or fail if the `data` file is a "future" version.
- `src/writer`: a program that will write to the `data` file with the latest version.
- `src/serializer`: a package that contains serialization and versioning code for the example.

Using this codebase, the following things can be demoed:
- Adding fields to a struct
- Removing fields from a struct
- Converting field types (example: a single f32 converted to an array of f32s)
- Moving an already serialized struct to another struct
  - `Foo` moves to `Collection.Foo`
  - This is cool cause it shows how a restructure can be versioned
-  Attempting to read from a "future version" in an "older version" of the reader app gets an error
- Accounting for fields that are added, but then later removed

The commit history of the `src/serializer/serializer.odin` file might also better illustrate versioning over time.
