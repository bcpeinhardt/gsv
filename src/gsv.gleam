import internal/ast
import internal/token
import gleam/list
import gleam/string

pub fn to_lists(input: String) -> Result(List(List(String)), Nil) {
  input
  |> token.scan
  |> ast.parse
}

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

pub fn from_lists(
  input: List(List(String)),
  separator separator: String,
  line_ending line_ending: LineEnding,
) -> String {
  input
  |> list.map(fn(row) {
    list.map(
      row,
      fn(entry) {
        // Double quotes need to be escaped with an extra doublequote
        let entry = string.replace(entry, "\"", "\"\"")

        // If the string contains a , \n \r or " it needs to be escaped by wrapping in double quotes
        case
          string.contains(entry, separator) || string.contains(
            entry,
            le_to_string(line_ending),
          ) || string.contains(entry, "\"")
        {
          True -> "\"" <> entry <> "\""
          False -> entry
        }
      },
    )
  })
  |> list.map(fn(row) { string.join(row, separator) })
  |> string.join(le_to_string(line_ending))
}
