# gsv

[![Package Version](https://img.shields.io/hexpm/v/gsv)](https://hex.pm/packages/gsv)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gsv/)

This is a simple csv parser and writer for Gleam. It will get more performant/battle tested in the future,
but if you're looking for that now, I'd recommend doing ffi to an existing parser in your target runtime.

#### Example

```gleam
import gsv.{Unix, Windows}

pub fn main() {
  let csv_str =
    "Hello,World
Goodbye,Mars"

  // Parse a CSV string to a List(List(String))
  let assert Ok(records) = gsv.to_lists(csv_str)

  // Write a List(List(String)) to a CSV string
  let csv_str = records
  |> gsv.from_lists(separator: ",", line_ending: Windows)

  // Parse a CSV string with headers to a List(Dict(String, String))
  let assert Ok(records) = gsv.to_dicts(csv_str)
  // => [ dict.from_list([ #("Hello", "Goodbye"), #("World", "Mars") ]) ]

  // Write a List(Dict(String, String)) to a CSV string, treating the keys as the header row
  let csv_str = records
    |> gsv.from_dicts(separator: ",", line_ending: Windows)
}
```

## Installation

If available on Hex this package can be added to your Gleam project:

```sh
gleam add gsv
```

and its documentation can be found at <https://hexdocs.pm/gsv>.
