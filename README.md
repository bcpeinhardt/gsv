# csv

[![Package Version](https://img.shields.io/hexpm/v/csv)](https://hex.pm/packages/csv)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/csv/)

This is a simple csv parser for gleam. It will get more performant in the future,
but if you're looking for high performance now, I'd recommend doing ffi to an existing parser
in your target runtime.

```gleam
"Ben, 25,\" TRUE\n\r\"\"\"\nAustin, 25, FALSE"
  |> csv.csv_to_lists
  |> should.equal(Ok([
    ["Ben", " 25", " TRUE\n\r\""],
    ["Austin", " 25", " FALSE"],
  ]))
```

## Quick start

```sh
gleam run   # Run the project
gleam test  # Run the tests
gleam shell # Run an Erlang shell
```

## Installation

If available on Hex this package can be added to your Gleam project:

```sh
gleam add csv
```

and its documentation can be found at <https://hexdocs.pm/csv>.
