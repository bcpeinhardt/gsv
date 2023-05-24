import internal/ast
import internal/token
import gleam/list
import gleam/string

pub fn to_lists(input: String) -> Result(List(List(String)), Nil) {
  input
  |> token.scan
  |> ast.parse
}

pub fn from_lists(
  input: List(List(String)),
  delimiter delimiter: String,
  line_ending line_ending: String,
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
          string.contains(entry, ",") || string.contains(entry, "\n") || string.contains(
            entry,
            "\r",
          ) || string.contains(entry, "\"")
        {
          True -> "\"" <> entry <> "\""
          False -> entry
        }
      },
    )
  })
  |> list.map(fn(row) { string.join(row, delimiter) })
  |> string.join(line_ending)
}
