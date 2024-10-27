import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string
import glearray

// --- TYPES -------------------------------------------------------------------

pub type ParseError {
  /// This error can occur if there is a csv field contains an unescaped double
  /// quote `"`.
  ///
  /// A field can contain a double quote only if it is escaped (that is,
  /// surrounded by double quotes). For example `wibb"le` would be an invalid
  /// field, the correct way to write such a field would be like this:
  /// `"wibb""le"`.
  ///
  UnescapedQuote(
    /// The byte index of the unescaped double.
    ///
    position: Int,
  )

  /// This error can occur when the file ends without the closing `"` of an
  /// escaped field. For example: `"hello`.
  ///
  UnclosedEscapedField(
    /// The byte index of the start of the unclosed escaped field.
    ///
    start: Int,
  )
}

/// Possible line endings used when turning a parsed csv back into a string
/// with the `from_lists` and `from_dicts` functions.
///
pub type LineEnding {
  /// The CRLF line ending: `\r\n`.
  ///
  Windows

  /// The LF line ending: `\n`.
  Unix
}

fn line_ending_to_string(le: LineEnding) -> String {
  case le {
    Windows -> "\r\n"
    Unix -> "\n"
  }
}

// --- PARSING -----------------------------------------------------------------

/// Parses a csv string into a list of lists of strings: each line of the csv
/// will be turned into a list with an item for each field.
///
/// ## Examples
///
/// ```gleam
/// "hello, world
/// goodbye, mars"
/// |> gsv.to_lists
/// // Ok([
/// //    ["hello", " world"],
/// //    ["goodbye", " mars"],
/// // ])
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
  /// We're in the middle of parsing an escaped csv field (that is, starting
  /// and ending with `"`).
  ///
  ParsingEscapedField

  /// We're in the middle of parsing a regular csv field.
  ///
  ParsingUnescapedField

  /// We've just ran into a (non escaped) comma, signalling the end of a field.
  ///
  CommaFound

  /// We've just ran into a (non escaped) newline (either a `\n` or `\r\n`),
  /// signalling the end of a line and the start of a new one.
  ///
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
    // If we were parsing an escaped field then escaped quotes must be replaced
    // with a single one.
    ParsingEscapedField -> string.replace(in: field, each: "\"\"", with: "\"")
  }
}

/// Parses a csv string into a list of dicts: the first line of the csv is
/// interpreted as the headers' row and each of the following lines is turned
/// into a dict with a value for each of the headers.
///
/// If a field is empty then it won't be added to the dict.
///
/// ## Examples
///
/// ```gleam
/// "pet,name,cuteness
/// dog,Fido,100
/// cat,,1000
/// "
/// |> gsv.to_dicts
/// // Ok([
/// //    dict.from_list([
/// //      #("pet", "dog"), #("name", "Fido"), #("cuteness", "100")
/// //    ]),
/// //    dict.from_list([
/// //      #("pet", "cat"), #("cuteness", "1000")
/// //    ]),
/// // ])
/// ```
///
/// > Just list `to_lists` this implementation tries to stick as closely as
/// > possible to [RFC4180](https://www.ietf.org/rfc/rfc4180.txt).
/// > You can look at `to_lists`' documentation to see how it differs from the
/// > RFC.
///
pub fn to_dicts(input: String) -> Result(List(Dict(String, String)), ParseError) {
  use rows <- result.map(to_lists(input))
  case rows {
    [] -> []
    [headers, ..rows] -> {
      let headers = glearray.from_list(headers)

      use row <- list.map(rows)
      use row, field, index <- list.index_fold(row, dict.new())
      case field {
        // If the field is empty then we don't add it to the row's dict.
        "" -> row
        _ ->
          // We look for the header corresponding to this field's position.
          case glearray.get(headers, index) {
            Ok(header) -> dict.insert(row, header, field)
            // This could happen if the row has more fields than headers in the
            // header row, in this case the field is just discarded
            Error(_) -> row
          }
      }
    }
  }
}

/// Takes a list of lists of strings and turns it to a csv string, automatically
/// escaping all fields that contain double quotes or line endings.
///
/// ## Examples
///
/// ```gleam
/// let rows = [["hello", "world"], ["goodbye", "mars"]]
/// from_lists(rows, separator: ",", line_ending: Unix)
/// // "hello,world
/// // goodbye,mars"
/// ```
///
/// ```gleam
/// let rows = [[]]
/// ```
///
pub fn from_lists(
  rows: List(List(String)),
  separator separator: String,
  line_ending line_ending: LineEnding,
) -> String {
  let line_ending = line_ending_to_string(line_ending)
  do_from_lists(rows, separator, line_ending, [])
  |> list.reverse
  |> string.join(with: "")
}

fn do_from_lists(
  rows: List(List(String)),
  separator: String,
  line_ending: String,
  acc: List(String),
) -> List(String) {
  case rows {
    [] -> acc
    // When we're down to the last row, we don't add a final newline at the end
    // of the string. So we special handle this case and pass in an empty string
    // as the `line_ending` to add to the row.
    [last_row] -> row_to_string(last_row, separator, "", acc)
    // For all other cases we just accumulate the line string onto the string
    // accumulator.
    [row, ..rest] -> {
      let acc = row_to_string(row, separator, line_ending, acc)
      do_from_lists(rest, separator, line_ending, acc)
    }
  }
}

fn row_to_string(
  row: List(String),
  separator: String,
  line_ending: String,
  acc: List(String),
) -> List(String) {
  case row {
    [] -> acc

    // When we're down to the last field of the row we need to add the line
    // ending instead of the field separator. So we special handle this case.
    [last_field] -> [line_ending, escape_field(last_field, separator), ..acc]

    // For all other cases we add the field to the accumulator and append a
    // separator to separate it from the next field in the row.
    [field, ..rest] -> {
      let acc = [separator, escape_field(field, separator), ..acc]
      row_to_string(rest, separator, line_ending, acc)
    }
  }
}

/// The kind of escaping needed by a csv field.
///
type Escaping {
  NoEscaping
  WrapInDoubleQuotes
  WrapInDoubleQuotesAndEscapeDoubleQuotes
}

fn escape_field(field: String, separator: String) -> String {
  case escaping(field, separator) {
    NoEscaping -> field
    WrapInDoubleQuotes -> "\"" <> field <> "\""
    WrapInDoubleQuotesAndEscapeDoubleQuotes ->
      "\"" <> string.replace(in: field, each: "\"", with: "\"\"") <> "\""
  }
}

fn escaping(string: String, separator: String) -> Escaping {
  case string.contains(string, separator) {
    True -> do_escaping(string, WrapInDoubleQuotes)
    False -> do_escaping(string, NoEscaping)
  }
}

fn do_escaping(string: String, kind: Escaping) {
  case string {
    // As soon as we find a double quote we know that we must escape the double
    // quotes and wrap it in double quotes, no need to keep going through the
    // string.
    "\"" <> _ -> WrapInDoubleQuotesAndEscapeDoubleQuotes
    // If we find a newline we know the string must at least be wrapped in
    // double quotes but we keep going in case we find a `"`.
    "\n" <> rest -> do_escaping(rest, WrapInDoubleQuotes)
    // If we reach the end of the string we return the accumulator.
    "" -> kind
    // In all other cases we keep looking.
    _ -> do_escaping(drop_bytes(string, 1), kind)
  }
}

/// Takes a list of dicts and writes it to a csv string.
/// Will automatically escape strings that contain double quotes or
/// line endings with double quotes (in csv, double quotes get escaped by doing
/// a double doublequote)
/// The string `he"llo\n` becomes `"he""llo\n"`
///
pub fn from_dicts(
  rows: List(Dict(String, String)),
  separator separator: String,
  line_ending line_ending: LineEnding,
) -> String {
  case rows {
    [] -> ""
    _ -> {
      let headers =
        rows
        |> list.flat_map(dict.keys)
        |> list.unique
        |> list.sort(string.compare)

      let rows = list.map(rows, row_dict_to_list(_, headers))
      from_lists([headers, ..rows], separator, line_ending)
    }
  }
}

fn row_dict_to_list(
  row: Dict(String, String),
  headers: List(String),
) -> List(String) {
  use header <- list.map(headers)
  case dict.get(row, header) {
    Ok(field) -> field
    Error(Nil) -> ""
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
@external(javascript, "./gsv_ffi.mjs", "slice")
fn slice_bytes(string: String, from: Int, length: Int) -> String

@external(erlang, "gsv_ffi", "drop_bytes")
@external(javascript, "./gsv_ffi.mjs", "drop_bytes")
fn drop_bytes(string: String, bytes: Int) -> String
