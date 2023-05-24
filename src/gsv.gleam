import gsv/ast
import gsv/token

pub fn to_lists(input: String) -> Result(List(List(String)), Nil) {
  input
  |> token.scan
  |> ast.parse
}
