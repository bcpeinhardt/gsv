# csv

[![Package Version](https://img.shields.io/hexpm/v/csv)](https://hex.pm/packages/csv)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/csv/)

This is a simple csv parser for gleam. It will get more performant in the future,
but if you're looking for high performance now, I'd recommend doing ffi to an existing parser
in your target runtime.

We are using the following grammar for CSV from rfc4180
file = [header CRLF] record *(CRLF record) [CRLF]
header = name *(COMMA name)
record = field *(COMMA field)
name = field
field = (escaped / non-escaped)
escaped = DQUOTE *(TEXTDATA / COMMA / CR / LF / 2DQUOTE) DQUOTE
non-escaped = *TEXTDATA

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
