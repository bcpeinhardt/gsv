import gleam/map.{Map}
import gleam/list
import gleam/result

import ast
import token

pub fn csv_to_lists(input: String) -> Result(List(List(String)), Nil) {
  input
  |> token.scan
  |> ast.parse
}
