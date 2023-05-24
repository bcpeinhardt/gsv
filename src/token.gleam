//// We are using the following grammar for CSV
////
//// csv       = line (newline line)*
//// line      = field (comma field)*
//// field     = escaped / nonescaped
//// escaped   = doublequote *(TEXTDATA / comma / newline / CR / doublequote doublequote) doublequote
//// nonescaped = *(TEXTDATA)
//// comma     = ','
//// newline   = '\n'
//// CR        = '\r'
//// doublequote = '"'
//// TEXTDATA  = <any character except comma, newline, CR, doublequote>

import gleam/string
import gleam/list

pub type CsvToken {
  Comma
  Newline
  CR
  Doublequote
  Textdata(inner: String)
}

pub fn to_lexeme(token: CsvToken) -> String {
  case token {
    Comma -> ","
    Newline -> "\n"
    CR -> "\r"
    Doublequote -> "\""
    Textdata(str) -> str
  }
}

pub fn scan(csv: String) -> List(CsvToken) {
  csv
  |> string.to_graphemes()
  |> list.fold(
    [],
    fn(acc, x) {
      case x {
        "," -> [Comma, ..acc]
        "\n" -> [Newline, ..acc]
        "\r" -> [CR, ..acc]
        "\"" -> [Doublequote, ..acc]
        x -> {
          case acc {
            [Textdata(str), ..rest] -> [Textdata(str <> x), ..rest]
            _ -> [Textdata(x), ..acc]
          }
        }
      }
    },
  )
  |> list.reverse
}
