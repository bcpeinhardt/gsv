import gsv/internal/ast.{ParseError}
import gsv/internal/token.{Location}
import gleam/list
import gleam/string
import gleam/result
import gleam/int

/// Parses a csv string to a list of lists of strings.
/// Automatically handles Windows and Unix line endings.
pub fn to_lists(input: String) -> Result(List(List(String)), Nil) {
  input
  |> token.scan
  |> token.with_location
  |> ast.parse
  |> result.nil_error
}

/// Parses a csv string to a list of lists of strings.
/// Automatically handles Windows and Unix line endings.
/// Panics with an error msg if the string is not valid csv.
pub fn to_lists_or_panic(input: String) -> List(List(String)) {
  let res =
    input
    |> token.scan
    |> token.with_location
    |> ast.parse

  case res {
    Ok(lol) -> lol
    Error(ParseError(Location(line, column), msg)) -> {
      panic as {
        "["
        <> "line "
        <> int.to_string(line)
        <> " column "
        <> int.to_string(column)
        <> "] of csv: "
        <> msg
      }
      [[]]
    }
  }
}

/// Parses a csv string to a list of lists of strings.
/// Automatically handles Windows and Unix line endings.
/// Returns a string error msg if the string is not valid csv.
pub fn to_lists_or_error(input: String) -> Result(List(List(String)), String) {
  input
  |> token.scan
  |> token.with_location
  |> ast.parse
  |> result.map_error(fn(e) {
    let ParseError(Location(line, column), msg) = e
    "["
    <> "line "
    <> int.to_string(line)
    <> " column "
    <> int.to_string(column)
    <> "] of csv: "
    <> msg
  })
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
