//// We are using the following grammar for CSV from rfc4180
////
//// file = [header CRLF] record *(CRLF record) [CRLF]
////   header = name *(COMMA name)
////  record = field *(COMMA field)
////  name = field
////  field = (escaped / non-escaped)
////  escaped = DQUOTE *(TEXTDATA / COMMA / CR / LF / 2DQUOTE) DQUOTE
////  non-escaped = *TEXTDATA

import gleam/list
import gleam/string

pub type CsvToken {
  Comma
  LF
  CR
  Doublequote
  Textdata(inner: String)
}

pub type Location {
  Location(line: Int, column: Int)
}

pub fn to_lexeme(token: CsvToken) -> String {
  case token {
    Comma -> ","
    LF -> "\n"
    CR -> "\r"
    Doublequote -> "\""
    Textdata(str) -> str
  }
}

fn len(token: CsvToken) -> Int {
  case token {
    Comma -> 1
    LF -> 1
    CR -> 1
    Doublequote -> 1
    Textdata(str) -> string.length(str)
  }
}

pub fn scan(input: String) -> List(CsvToken) {
  input
  |> string.to_utf_codepoints
  |> list.fold([], fn(acc, x) {
    case string.utf_codepoint_to_int(x) {
      0x2c -> [Comma, ..acc]
      0x22 -> [Doublequote, ..acc]
      0x0a -> [LF, ..acc]
      0x0D -> [CR, ..acc]
      _ -> {
        let cp = string.from_utf_codepoints([x])
        case acc {
          [Textdata(str), ..rest] -> [Textdata(str <> cp), ..rest]
          _ -> [Textdata(cp), ..acc]
        }
      }
    }
  })
  |> list.reverse
}

pub fn with_location(input: List(CsvToken)) -> List(#(CsvToken, Location)) {
  do_with_location(input, [], Location(1, 1))
  |> list.reverse
}

fn do_with_location(
  input: List(CsvToken),
  acc: List(#(CsvToken, Location)),
  curr_loc: Location,
) -> List(#(CsvToken, Location)) {
  let Location(line, column) = curr_loc
  case input {
    // Base case, no more tokens
    [] -> acc

    // A newline, increment line number
    [LF, ..rest] -> {
      do_with_location(rest, [#(LF, curr_loc), ..acc], Location(line + 1, 1))
    }
    [CR, LF, ..rest] -> {
      do_with_location(
        rest,
        [#(LF, Location(line, column + 1)), #(CR, curr_loc), ..acc],
        Location(line + 1, 1),
      )
    }

    // Any other token just increment the column
    [token, ..rest] -> {
      do_with_location(
        rest,
        [#(token, curr_loc), ..acc],
        Location(line, column + len(token)),
      )
    }
  }
}
