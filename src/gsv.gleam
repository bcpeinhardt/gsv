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

/// Possible field separators used when parsing csv data
///
pub type FieldSeparator {
  /// RFC4180 field separator
  Comma

  /// Tab seperated fields
  Tab

  /// Custom seperator
  Custom(String)
}

fn field_separator_to_string(fs: FieldSeparator) -> String {
  case fs {
    Comma -> ","
    Tab -> "\t"
    Custom(sep) -> sep
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
/// > - lines are not forced to all have the same number of fields.
/// > - a line can end with a comma (meaning its last field is empty).
///
pub fn to_lists(
  input: String,
  field_separator: FieldSeparator,
) -> Result(List(List(String)), ParseError) {
  let sep = field_separator_to_string(field_separator)
  case input, string.starts_with(input, sep) {
    // We just ignore all unescaped newlines at the beginning of a file.
    "\n" <> rest, _ | "\r\n" <> rest, _ -> to_lists(rest, field_separator)
    // If it starts with a `"` then we know it starts with an escaped field.
    "\"" <> rest, _ ->
      do_parse(rest, input, 1, 0, [], [], ParsingEscapedField, sep)
    // If it starts with a field seperator then it starts with an empty field we're filling
    // out manually.
    rest, True ->
      do_parse(
        string.drop_start(rest, string.length(sep)),
        input,
        1,
        0,
        [""],
        [],
        SeparatorFound,
        sep,
      )
    // Otherwise we just start parsing the first unescaped field.
    _, False -> do_parse(input, input, 0, 0, [], [], ParsingUnescapedField, sep)
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

  /// We've just ran into a (non escaped) field separator, signalling the end of a field.
  ///
  SeparatorFound

  /// We've just ran into a (non escaped) newline (either a `\n` or `\r\n`),
  /// signalling the end of a line and the start of a new one.
  ///
  NewlineFound
}

/// This is used to keep track of whether a separator was observed at the head of the input.
///
type SepStatus {
  /// An escaped field has ended followed by a field seperator
  ///
  QuotSep

  /// A field separator was observed
  ///
  Sep

  /// No field separator was observed
  NoSep
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
  field_separator: String,
) -> Result(List(List(String)), ParseError) {
  let sep_len = string.length(field_separator)
  let #(remaining, skip, sep) = case
    string.starts_with(string, field_separator)
  {
    True -> #(string.drop_start(string, sep_len), sep_len, Sep)
    False ->
      case string.starts_with(string, "\"" <> field_separator) {
        True -> #(string.drop_start(string, sep_len + 1), sep_len + 1, QuotSep)
        False -> #(string, 0, NoSep)
      }
  }
  case remaining, status, sep {
    // If we find a separator we're done with the current field and can take a slice
    // going from `field_start` with `field_length` bytes:
    //
    //     wibble<sep>wobble,...
    //     ╰────╯ field_length = 6
    //     ┬
    //     ╰ field_start
    //
    // After taking the slice we move the slice start _after_ the comma:
    //
    //     wibble<sep>wobble,...
    //                ┬
    //                ╰ field_start = field_start + field_length + skip (the length of the separator)
    //
    rest, SeparatorFound, Sep
    | rest, NewlineFound, Sep
    | rest, ParsingUnescapedField, Sep
    | rest, ParsingEscapedField, QuotSep
    -> {
      let field = extract_field(original, field_start, field_length, status)
      let row = [field, ..row]
      let start = field_start + field_length + skip
      do_parse(
        rest,
        original,
        start,
        0,
        row,
        rows,
        SeparatorFound,
        field_separator,
      )
    }

    // When the string is over we're done parsing.
    // We take the final field we were in the middle of parsing and add it to
    // the current row that is returned together with all the parsed rows.
    //
    "", ParsingUnescapedField, NoSep | "\"", ParsingEscapedField, NoSep -> {
      let field = extract_field(original, field_start, field_length, status)
      let row = list.reverse([field, ..row])
      Ok(list.reverse([row, ..rows]))
    }

    "", SeparatorFound, NoSep -> {
      let row = list.reverse(["", ..row])
      Ok(list.reverse([row, ..rows]))
    }

    "", NewlineFound, NoSep -> Ok(list.reverse(rows))

    // If the string is over and we were parsing an escaped field, that's an
    // error. We would expect to find a closing double quote before the end of
    // the data.
    //
    "", ParsingEscapedField, NoSep -> Error(UnclosedEscapedField(field_start))

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
    "\n" <> rest, ParsingUnescapedField, NoSep -> {
      let field = extract_field(original, field_start, field_length, status)
      let row = list.reverse([field, ..row])
      let rows = [row, ..rows]
      let field_start = field_start + field_length + 1
      do_parse(
        rest,
        original,
        field_start,
        0,
        [],
        rows,
        NewlineFound,
        field_separator,
      )
    }
    "\r\n" <> rest, ParsingUnescapedField, NoSep
    | "\"\n" <> rest, ParsingEscapedField, NoSep
    -> {
      let field = extract_field(original, field_start, field_length, status)
      let row = list.reverse([field, ..row])
      let rows = [row, ..rows]
      let field_start = field_start + field_length + 2
      do_parse(
        rest,
        original,
        field_start,
        0,
        [],
        rows,
        NewlineFound,
        field_separator,
      )
    }
    "\"\r\n" <> rest, ParsingEscapedField, NoSep -> {
      let field = extract_field(original, field_start, field_length, status)
      let row = list.reverse([field, ..row])
      let rows = [row, ..rows]
      let field_start = field_start + field_length + 3
      do_parse(
        rest,
        original,
        field_start,
        0,
        [],
        rows,
        NewlineFound,
        field_separator,
      )
    }

    // If the newlines is immediately after a field separator then the row ends with an
    // empty field.
    //
    "\n" <> rest, SeparatorFound, NoSep -> {
      let row = list.reverse(["", ..row])
      let rows = [row, ..rows]
      do_parse(
        rest,
        original,
        field_start + 1,
        0,
        [],
        rows,
        NewlineFound,
        field_separator,
      )
    }
    "\r\n" <> rest, SeparatorFound, NoSep -> {
      let row = list.reverse(["", ..row])
      let rows = [row, ..rows]
      do_parse(
        rest,
        original,
        field_start + 2,
        0,
        [],
        rows,
        NewlineFound,
        field_separator,
      )
    }

    // If the newline immediately comes after a newline that means we've run
    // into an empty line that we can just safely ignore.
    //
    "\n" <> rest, NewlineFound, NoSep ->
      do_parse(
        rest,
        original,
        field_start + 1,
        0,
        row,
        rows,
        status,
        field_separator,
      )
    "\r\n" <> rest, NewlineFound, NoSep ->
      do_parse(
        rest,
        original,
        field_start + 2,
        0,
        row,
        rows,
        status,
        field_separator,
      )

    // An escaped quote found while parsing an escaped field.
    //
    "\"\"" <> rest, ParsingEscapedField, NoSep ->
      do_parse(
        rest,
        original,
        field_start,
        field_length + 2,
        row,
        rows,
        status,
        field_separator,
      )

    // An unescaped quote found while parsing a field.
    //
    "\"" <> _, ParsingUnescapedField, NoSep
    | "\"" <> _, ParsingEscapedField, NoSep
    -> Error(UnescapedQuote(position: field_start + field_length))

    // If the quote is found immediately after a field separator or a newline that signals
    // the start of a new escaped field to parse.
    //
    "\"" <> rest, SeparatorFound, NoSep | "\"" <> rest, NewlineFound, NoSep -> {
      do_parse(
        rest,
        original,
        field_start + 1,
        0,
        row,
        rows,
        ParsingEscapedField,
        field_separator,
      )
    }

    // In all other cases we're still parsing a field so we just drop a byte
    // from the string we're iterating through, increase the size of the slice
    // we need to take and keep going.
    //
    // > ⚠️ Notice how we're not trying to trim any whitespaces at the
    // > beginning or end of a field: RFC 4810 states that "Spaces are
    // > considered part of a field and should not be ignored."
    //
    _, SeparatorFound, _
    | _, NewlineFound, _
    | _, ParsingUnescapedField, _
    | _, ParsingEscapedField, _
    -> {
      let status = case status {
        ParsingEscapedField -> ParsingEscapedField
        SeparatorFound | NewlineFound | ParsingUnescapedField ->
          ParsingUnescapedField
      }
      let rest = drop_bytes(string, 1)
      do_parse(
        rest,
        original,
        field_start,
        field_length + 1,
        row,
        rows,
        status,
        field_separator,
      )
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
    SeparatorFound | ParsingUnescapedField | NewlineFound -> field
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
pub fn to_dicts(
  input: String,
  field_separator: FieldSeparator,
) -> Result(List(Dict(String, String)), ParseError) {
  use rows <- result.map(to_lists(input, field_separator))
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
  separator separator: FieldSeparator,
  line_ending line_ending: LineEnding,
) -> String {
  let line_ending = line_ending_to_string(line_ending)
  let sep = field_separator_to_string(separator)

  list.map(rows, fn(row) {
    list.map(row, escape_field(_, sep))
    |> string.join(with: sep)
  })
  |> string.join(with: line_ending)
  |> string.append(line_ending)
}

fn escape_field(field: String, separator: String) -> String {
  case string.contains(field, "\"") {
    True -> "\"" <> string.replace(in: field, each: "\"", with: "\"\"") <> "\""
    False ->
      case string.contains(field, separator) || string.contains(field, "\n") {
        True -> "\"" <> field <> "\""
        False -> field
      }
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
  separator separator: FieldSeparator,
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
/// However, the parser only slices fields in between separators so it should always
/// yield valid utf8 slices.
///
@external(erlang, "gsv_ffi", "slice")
@external(javascript, "./gsv_ffi.mjs", "slice")
fn slice_bytes(string: String, from: Int, length: Int) -> String

@external(erlang, "gsv_ffi", "drop_bytes")
@external(javascript, "./gsv_ffi.mjs", "drop_bytes")
fn drop_bytes(string: String, bytes: Int) -> String
