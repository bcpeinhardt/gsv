//// We are using the following grammar for CSV
////
//// csv       = line (newline line)*
//// line      = field (comma field)*
//// field     = escaped / nonescaped
//// escaped   = doublequote *(TEXTDATA / comma / newline / doublequote doublequote) doublequote
//// nonescaped = *(TEXTDATA)
//// comma     = ','
//// newline   = '\n'
//// doublequote = '"'
//// TEXTDATA  = <any character except comma, newline, doublequote>

import gleam/list
import gleam/result
import token.{Comma, CsvToken, Doublequote, Newline, Textdata}

type ParseState {
  Beginning
  JustParsedField
  JustParsedComma
  JustParsedNewline
  InsideEscapedString
}

pub fn parse(input: List(CsvToken)) -> Result(List(List(String)), Nil) {
  let inner_rev = {
    use llf <- result.try(parse_p(input, Beginning, []))
    use lf <- list.try_map(llf)
    Ok(list.reverse(lf))
  }
  use ir <- result.try(inner_rev)
  Ok(list.reverse(ir))
}

fn parse_p(
  input: List(CsvToken),
  parse_state: ParseState,
  llf: List(List(String)),
) -> Result(List(List(String)), Nil) {
  case input, parse_state, llf {
    // Error Case: An empty list should produce an Error
    [], Beginning, _ -> Error(Nil)

    // BASE CASE: We are done parsing tokens
    [], _, llf -> Ok(llf)

    // File should begin with either Escaped or Nonescaped string
    [Textdata(str), ..remaining_tokens], Beginning, [] ->
      parse_p(remaining_tokens, JustParsedField, [[str]])

    [Doublequote, ..remaining_tokens], Beginning, [] ->
      parse_p(remaining_tokens, InsideEscapedString, [[""]])

    _, Beginning, _ -> Error(Nil)

    // If we just parsed a field, we're expecting either a comma or a newline
    [Comma, ..remaining_tokens], JustParsedField, llf ->
      parse_p(remaining_tokens, JustParsedComma, llf)

    [Newline, ..remaining_tokens], JustParsedField, llf ->
      parse_p(remaining_tokens, JustParsedNewline, llf)

    _, JustParsedField, _ -> Error(Nil)

    // If we just parsed a comma, we're expecting an Escaped or Non-Escaped string
    [Textdata(str), ..remaining_tokens], JustParsedComma, [
      curr_line,
      ..previously_parsed_lines
    ] ->
      parse_p(
        remaining_tokens,
        JustParsedField,
        [[str, ..curr_line], ..previously_parsed_lines],
      )

    [Doublequote, ..remaining_tokens], JustParsedComma, [
      curr_line,
      ..previously_parsed_lines
    ] ->
      parse_p(
        remaining_tokens,
        InsideEscapedString,
        [["", ..curr_line], ..previously_parsed_lines],
      )

    _, JustParsedComma, _ -> Error(Nil)

    // If we just parsed a new line, we're expecting an escaped or non-escaped string
    [Textdata(str), ..remaining_tokens], JustParsedNewline, llf ->
      parse_p(remaining_tokens, JustParsedField, [[str], ..llf])

    [Doublequote, ..remaining_tokens], JustParsedNewline, [
      curr_line,
      ..previously_parsed_lines
    ] ->
      parse_p(
        remaining_tokens,
        InsideEscapedString,
        [["", ..curr_line], ..previously_parsed_lines],
      )

    _, JustParsedNewline, _ -> Error(Nil)

    // If we're inside an escaped string, we can take anything until we get a double quote,
    // but a double double quote "" escapes the double quote and we keep parsing
    [Doublequote, Doublequote, ..remaining_tokens], InsideEscapedString, [
      [str, ..rest_curr_line],
      ..previously_parsed_lines
    ] ->
      parse_p(
        remaining_tokens,
        InsideEscapedString,
        [[str <> "\"", ..rest_curr_line], ..previously_parsed_lines],
      )

    [Doublequote, ..remaining_tokens], InsideEscapedString, llf ->
      parse_p(remaining_tokens, JustParsedField, llf)

    [other_token, ..remaining_tokens], InsideEscapedString, [
      [str, ..rest_curr_line],
      ..previously_parsed_lines
    ] ->
      parse_p(
        remaining_tokens,
        InsideEscapedString,
        [
          [str <> token.to_lexeme(other_token), ..rest_curr_line],
          ..previously_parsed_lines
        ],
      )
  }
}
