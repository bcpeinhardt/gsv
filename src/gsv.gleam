import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gsv/internal/parse

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
pub fn to_lists(input: String) -> Result(List(List(String)), String) {
  parse.parse(input)
  |> result.map_error(fn(error) {
    io.debug(error)
    todo as "decide what to do with errors"
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
