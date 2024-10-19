import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string

// --- TYPES -------------------------------------------------------------------

pub type ParseError {
  /// A field can contain a double quote only if it is escaped (that is,
  /// surrounded by double quotes). For example `wobb"le` would be an invalid
  /// field, the correct way to write such a field would be like this:
  /// `"wobb""le"`.
  ///
  UnescapedQuote(
    /// The byte index of the unescaped double.
    position: Int,
  )

  /// This error can occur when the file ends without the closing `"` of an
  /// escaped field. For example: `"hello`.
  ///
  UnclosedEscapedField(
    /// The byte index of the start of the unclosed escaped field.
    start: Int,
  )
}

// --- PARSING -----------------------------------------------------------------

/// Parses a csv string into a list of lists of strings.
/// ## Examples
///
/// ```gleam
/// "hello, world
/// goodbye, mars
/// "
/// |> gsv.to_lists
/// // [["hello", " world"], ["goodbye", " mars"]]
/// ```
///
/// > This implementation tries to stick as closely as possible to
/// > [RFC4180](https://www.ietf.org/rfc/rfc4180.txt), with a couple notable
/// > convenience differences:
/// > - both `\n` and `\r\n` line endings are accepted.
/// > - a line can start with an empty field `,two,three`.
/// > - empty lines are allowed and just ignored.
///
pub fn to_lists(input: String) -> Result(List(List(String)), ParseError) {
  case input {
    // We just ignore all unescaped newlines at the beginning of a file.
    "\n" <> rest | "\r\n" <> rest -> to_lists(rest)
    // If it starts with a `"` then we know it starts with an escaped field.
    "\"" <> rest -> do_parse(rest, input, 1, 0, [], [], ParsingEscapedField)
    // If it starts with a `,` then it starts with an empty field we're filling
    // out manually.
    "," <> rest -> do_parse(rest, input, 1, 0, [""], [], CommaFound)
    // Otherwise we just start parsing the first unescaped field.
    _ -> do_parse(input, input, 0, 0, [], [], ParsingUnescapedField)
  }
}

/// This is used to keep track of what the parser is doing.
///
type ParseStatus {
  ParsingEscapedField
  ParsingUnescapedField
  CommaFound
  NewlineFound
}

/// ## What does this scary looking function do?
///
/// At a high level, it goes over the csv `string` byte-by-byte and parses rows
/// accumulating those into `rows` as it goes.
///
///
/// ## Why does it have all these parameters? What does each one do?
///
/// In order to be extra efficient this function parses the csv file in a single
/// pass and uses string slicing to avoid copying data.
/// Each time we see a new field we keep track of the byte where it starts with
/// `field_start` and then count the bytes (that's the `field_length` variable)
/// until we fiend its end (either a newline, the end of the file, or a `,`).
///
/// After reaching the end of a field we extract it from the original string
/// taking a slice that goes from `field_start` and has `field_length` bytes.
/// This is where the magic happens: slicing a string this way is a constant
/// time operation and doesn't copy the string so it's crazy fast!
///
/// `row` is an accumulator with all the fields of the current row as
/// they are parsed. Once we run into a newline `current_row` is added to all
/// the other `rows`.
///
/// We also keep track of _what_ we're parsing with the `status` to make
/// sure that we're correctly dealing with escaped fields and double quotes.
///
fn do_parse(
  string: String,
  original: String,
  field_start: Int,
  field_length: Int,
  row: List(String),
  rows: List(List(String)),
  status: ParseStatus,
) -> Result(List(List(String)), ParseError) {
  case string, status {
    // If we find a comma we're done with the current field and can take a slice
    // going from `field_start` with `field_length` bytes:
    //
    //     wibble,wobble,...
    //     ╰────╯ field_length = 6
    //     ┬
    //     ╰ field_start
    //
    // After taking the slice we move the slice start _after_ the comma:
    //
    //     wibble,wobble,...
    //            ┬
    //            ╰ field_start = field_start + field_length + 1 (the comma)
    //
    "," <> rest, CommaFound
    | "," <> rest, NewlineFound
    | "," <> rest, ParsingUnescapedField
    -> {
      let field = extract_field(original, field_start, field_length, status)
      let row = [field, ..row]
      let field_start = field_start + field_length + 1
      do_parse(rest, original, field_start, 0, row, rows, CommaFound)
    }
    "\"," <> rest, ParsingEscapedField -> {
      let field = extract_field(original, field_start, field_length, status)
      let row = [field, ..row]
      let field_start = field_start + field_length + 2
      do_parse(rest, original, field_start, 0, row, rows, CommaFound)
    }

    // When the string is over we're done parsing.
    // We take the final field we were in the middle of parsing and add it to
    // the current row that is returned together with all the parsed rows.
    //
    "", ParsingUnescapedField | "\"", ParsingEscapedField -> {
      let field = extract_field(original, field_start, field_length, status)
      let row = list.reverse([field, ..row])
      Ok(list.reverse([row, ..rows]))
    }

    "", CommaFound -> {
      let row = list.reverse(["", ..row])
      Ok(list.reverse([row, ..rows]))
    }

    "", NewlineFound -> Ok(list.reverse(rows))

    // If the string is over and we were parsing an escaped field, that's an
    // error. We would expect to find a closing double quote before the end of
    // the data.
    //
    "", ParsingEscapedField -> Error(UnclosedEscapedField(field_start))

    // When we run into a new line (CRLF or just LF) we know we're done with the
    // current field and take a slice of it, just like we did in the previous
    // branch!
    // The only difference is we also add the current `row` to all the other
    // ones and start with a new one.
    //
    // > ⚠️ As for RFC 4180 lines should only be delimited by a CRLF.
    // > Here we do something slightly different and also accept lines that are
    // > delimited by just LF too.
    //
    // The next three branches are the same except for the new `field_start`
    // that has to take into account the different lengths.
    // I tried writing it as `"\n" as sep | "\r\n" as sep | ...` and then taking
    // adding the lenght of that but it had a noticeable (albeit small) impact
    // on performance.
    //
    "\n" <> rest, ParsingUnescapedField -> {
      let field = extract_field(original, field_start, field_length, status)
      let row = list.reverse([field, ..row])
      let rows = [row, ..rows]
      let field_start = field_start + field_length + 1
      do_parse(rest, original, field_start, 0, [], rows, NewlineFound)
    }
    "\r\n" <> rest, ParsingUnescapedField | "\"\n" <> rest, ParsingEscapedField -> {
      let field = extract_field(original, field_start, field_length, status)
      let row = list.reverse([field, ..row])
      let rows = [row, ..rows]
      let field_start = field_start + field_length + 2
      do_parse(rest, original, field_start, 0, [], rows, NewlineFound)
    }
    "\"\r\n" <> rest, ParsingEscapedField -> {
      let field = extract_field(original, field_start, field_length, status)
      let row = list.reverse([field, ..row])
      let rows = [row, ..rows]
      let field_start = field_start + field_length + 3
      do_parse(rest, original, field_start, 0, [], rows, NewlineFound)
    }

    // If the newlines is immediately after a comma then the row ends with an
    // empty field.
    //
    "\n" <> rest, CommaFound -> {
      let row = list.reverse(["", ..row])
      let rows = [row, ..rows]
      do_parse(rest, original, field_start + 1, 0, [], rows, NewlineFound)
    }
    "\r\n" <> rest, CommaFound -> {
      let row = list.reverse(["", ..row])
      let rows = [row, ..rows]
      do_parse(rest, original, field_start + 2, 0, [], rows, NewlineFound)
    }

    // If the newline immediately comes after a newline that means we've run
    // into an empty line that we can just safely ignore.
    //
    "\n" <> rest, NewlineFound ->
      do_parse(rest, original, field_start + 1, 0, row, rows, status)
    "\r\n" <> rest, NewlineFound ->
      do_parse(rest, original, field_start + 2, 0, row, rows, status)

    // An escaped quote found while parsing an escaped field.
    //
    "\"\"" <> rest, ParsingEscapedField ->
      do_parse(rest, original, field_start, field_length + 2, row, rows, status)

    // An unescaped quote found while parsing a field.
    //
    "\"" <> _, ParsingUnescapedField | "\"" <> _, ParsingEscapedField ->
      Error(UnescapedQuote(position: field_start + field_length))

    // If the quote is found immediately after a comma or a newline that signals
    // the start of a new escaped field to parse.
    //
    "\"" <> rest, CommaFound | "\"" <> rest, NewlineFound -> {
      let status = ParsingEscapedField
      do_parse(rest, original, field_start + 1, 0, row, rows, status)
    }

    // In all other cases we're still parsing a field so we just drop a byte
    // from the string we're iterating through, increase the size of the slice
    // we need to take and keep going.
    //
    // > ⚠️ Notice how we're not trying to trim any whitespaces at the
    // > beginning or end of a field: RFC 4810 states that "Spaces are
    // > considered part of a field and should not be ignored."
    //
    _, CommaFound
    | _, NewlineFound
    | _, ParsingUnescapedField
    | _, ParsingEscapedField
    -> {
      let status = case status {
        ParsingEscapedField -> ParsingEscapedField
        CommaFound | NewlineFound | ParsingUnescapedField ->
          ParsingUnescapedField
      }
      let rest = drop_bytes(string, 1)
      do_parse(rest, original, field_start, field_length + 1, row, rows, status)
    }
  }
}

fn extract_field(
  string: String,
  from: Int,
  length: Int,
  status: ParseStatus,
) -> String {
  let field = slice_bytes(string, from, length)
  case status {
    CommaFound | ParsingUnescapedField | NewlineFound -> field
    ParsingEscapedField -> string.replace(in: field, each: "\"\"", with: "\"")
  }
}

/// Parses a csv string to a list of dicts.
/// Automatically handles Windows and Unix line endings.
/// Returns a string error msg if the string is not valid csv.
/// Unquoted strings are trimmed, while quoted strings have leading and trailing
/// whitespace preserved.
/// Whitespace only or empty strings are not valid headers and will be ignored.
/// Whitespace only or empty strings are not considered "present" in the csv row and
/// are not inserted into the row dict.
pub fn to_dicts(input: String) -> Result(List(Dict(String, String)), ParseError) {
  use lol <- result.try(to_lists(input))
  case lol {
    [] -> []
    [headers, ..rows] -> {
      let headers =
        list.index_fold(headers, dict.new(), fn(acc, x, i) {
          case string.trim(x) == "" {
            True -> acc
            False -> dict.insert(acc, i, x)
          }
        })

      list.map(rows, fn(row) {
        use acc, x, i <- list.index_fold(row, dict.new())
        case dict.get(headers, i) {
          Error(Nil) -> acc
          Ok(h) ->
            case string.trim(x) {
              "" -> acc
              t -> dict.insert(acc, string.trim(h), t)
            }
        }
      })
    }
  }
  |> Ok
}

/// Option for using "\n = LF = Unix" or "\r\n = CRLF = Windows"
/// line endings. Use with the `from_lists` function when
/// writing to a csv string.
pub type LineEnding {
  Windows
  Unix
}

fn le_to_string(le: LineEnding) -> String {
  case le {
    Windows -> "\r\n"
    Unix -> "\n"
  }
}

/// Takes a list of lists of strings and writes it to a csv string.
/// Will automatically escape strings that contain double quotes or
/// line endings with double quotes (in csv, double quotes get escaped by doing
/// a double doublequote)
/// The string `he"llo\n` becomes `"he""llo\n"`
pub fn from_lists(
  input: List(List(String)),
  separator separator: String,
  line_ending line_ending: LineEnding,
) -> String {
  input
  |> list.map(fn(row) {
    list.map(row, fn(entry) {
      // Double quotes need to be escaped with an extra doublequote
      let entry = string.replace(entry, "\"", "\"\"")

      // If the string contains a , \n \r\n or " it needs to be escaped by wrapping in double quotes
      case
        string.contains(entry, separator)
        || string.contains(entry, "\n")
        || string.contains(entry, "\"")
      {
        True -> "\"" <> entry <> "\""
        False -> entry
      }
    })
  })
  |> list.map(fn(row) { string.join(row, separator) })
  |> string.join(le_to_string(line_ending))
}

/// Takes a list of dicts and writes it to a csv string.
/// Will automatically escape strings that contain double quotes or
/// line endings with double quotes (in csv, double quotes get escaped by doing
/// a double doublequote)
/// The string `he"llo\n` becomes `"he""llo\n"`
pub fn from_dicts(
  input: List(Dict(String, String)),
  separator separator: String,
  line_ending line_ending: LineEnding,
) -> String {
  case input {
    [] -> ""
    _ -> {
      let headers =
        input
        |> list.map(dict.keys)
        |> list.flatten
        |> list.unique
        |> list.sort(string.compare)

      let rows =
        list.map(input, fn(row) {
          list.fold(headers, [], fn(acc, h) {
            case dict.get(row, h) {
              Ok(v) -> [v, ..acc]
              Error(Nil) -> ["", ..acc]
            }
          })
        })
        |> list.map(list.reverse)

      from_lists([headers, ..rows], separator, line_ending)
    }
  }
}

// --- FFI HELPERS -------------------------------------------------------------

/// In general this wouldn't be safe, by just slicing random bytes in the middle
/// of a utf8 string we might end up with something that is not a valid utf8
/// string.
/// However, the parser only slices fields in between commas so it should always
/// yield valid utf8 slices.
///
@external(erlang, "gsv_ffi", "slice")
@external(javascript, "../gsv_ffi.mjs", "slice")
fn slice_bytes(string: String, from: Int, length: Int) -> String

@external(erlang, "gsv_ffi", "drop_bytes")
@external(javascript, "../gsv_ffi.mjs", "drop_bytes")
fn drop_bytes(string: String, bytes: Int) -> String
