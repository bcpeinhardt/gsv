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
  |> list.map(fn(row) { string.join(row, delimiter) })
  |> string.join(line_ending)
}
