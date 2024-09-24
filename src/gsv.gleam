import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/pair
import gleam/result
import gleam/string
import gsv/internal/ast.{ParseError}
import gsv/internal/token.{Location}

/// Parses a csv string to a list of lists of strings.
/// Automatically handles Windows and Unix line endings.
/// Returns a string error msg if the string is not valid csv.
/// Unquoted strings are trimmed, while quoted strings have leading and trailing 
/// whitespace preserved.
pub fn to_lists(input: String) -> Result(List(List(String)), String) {
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

/// Parses a csv string to a list of dicts. 
/// Automatically handles Windows and Unix line endings.
/// Returns a string error msg if the string is not valid csv.
/// Unquoted strings are trimmed, while quoted strings have leading and trailing 
/// whitespace preserved.
/// Whitespace only or empty strings are not valid headers and will be ignored. 
/// Whitespace only or empty strings are not considered "present" in the csv row and 
/// are not inserted into the row dict. 
pub fn to_dicts(input: String) -> Result(List(Dict(String, String)), String) {
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
    [first_row, ..] -> {
      let headers =
        first_row
        |> dict.to_list
        |> list.map(pair.first)
        |> list.sort(string.compare)

      let rows =
        list.map(input, fn(row) {
          row
          |> dict.to_list
          |> list.sort(fn(lhs, rhs) {
            string.compare(pair.first(lhs), pair.first(rhs))
          })
          |> list.map(pair.second)
        })

      from_lists([headers, ..rows], separator, line_ending)
    }
  }
}
