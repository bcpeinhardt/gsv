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
import gleam/result
import gsv/internal/token.{
  type CsvToken, type Location, CR, Comma, Doublequote, LF, Location, Textdata,
}

type ParseState {
  Beginning
  JustParsedField
  JustParsedComma
  JustParsedNewline
  JustParsedCR
  InsideEscapedString
}

pub type ParseError {
  ParseError(location: Location, message: String)
}

pub fn parse(
  input: List(#(CsvToken, Location)),
) -> Result(List(List(String)), ParseError) {
  let inner_rev = {
    use llf <- result.try(parse_p(input, Beginning, []))
    use lf <- list.try_map(llf)
    Ok(list.reverse(lf))
  }
  use ir <- result.try(inner_rev)
  Ok(list.reverse(ir))
}

fn parse_p(
  input: List(#(CsvToken, Location)),
  parse_state: ParseState,
  llf: List(List(String)),
) -> Result(List(List(String)), ParseError) {
  case input, parse_state, llf {
    // Error Case: An empty list should produce an Error
    [], Beginning, _ -> Error(ParseError(Location(0, 0), "Empty input"))

    // BASE CASE: We are done parsing tokens
    [], _, llf -> Ok(llf)

    // File should begin with either Escaped or Nonescaped string
    [#(Textdata(str), _), ..remaining_tokens], Beginning, [] ->
      parse_p(remaining_tokens, JustParsedField, [[str]])

    [#(Doublequote, _), ..remaining_tokens], Beginning, [] ->
      parse_p(remaining_tokens, InsideEscapedString, [[""]])

    [#(tok, loc), ..], Beginning, _ ->
      Error(ParseError(
        loc,
        "Unexpected start to csv content: " <> token.to_lexeme(tok),
      ))

    // If we just parsed a field, we're expecting either a comma or a CRLF
    [#(Comma, _), ..remaining_tokens], JustParsedField, llf ->
      parse_p(remaining_tokens, JustParsedComma, llf)

    [#(LF, _), ..remaining_tokens], JustParsedField, llf ->
      parse_p(remaining_tokens, JustParsedNewline, llf)

    [#(CR, _), ..remaining_tokens], JustParsedField, llf ->
      parse_p(remaining_tokens, JustParsedCR, llf)

    [#(tok, loc), ..], JustParsedField, _ ->
      Error(ParseError(
        loc,
        "Expected comma or newline after field, found: " <> token.to_lexeme(tok),
      ))

    // If we just parsed a CR, we're expecting an LF
    [#(LF, _), ..remaining_tokens], JustParsedCR, llf ->
      parse_p(remaining_tokens, JustParsedNewline, llf)

    [#(tok, loc), ..], JustParsedCR, _ ->
      Error(ParseError(
        loc,
        "Expected \"\\n\" after \"\\r\", found: " <> token.to_lexeme(tok),
      ))

    // If we just parsed a comma, we're expecting an Escaped or Non-Escaped string
    [#(Textdata(str), _), ..remaining_tokens], JustParsedComma, [
      curr_line,
      ..previously_parsed_lines
    ] ->
      parse_p(remaining_tokens, JustParsedField, [
        [str, ..curr_line],
        ..previously_parsed_lines
      ])

    [#(Doublequote, _), ..remaining_tokens], JustParsedComma, [
      curr_line,
      ..previously_parsed_lines
    ] ->
      parse_p(remaining_tokens, InsideEscapedString, [
        ["", ..curr_line],
        ..previously_parsed_lines
      ])

    [#(tok, loc), ..], JustParsedComma, _ ->
      Error(ParseError(
        loc,
        "Expected escaped or non-escaped string after comma, found: " <> token.to_lexeme(
          tok,
        ),
      ))

    // If we just parsed a new line, we're expecting an escaped or non-escaped string
    [#(Textdata(str), _), ..remaining_tokens], JustParsedNewline, llf ->
      parse_p(remaining_tokens, JustParsedField, [[str], ..llf])

    [#(Doublequote, _), ..remaining_tokens], JustParsedNewline, [
      curr_line,
      ..previously_parsed_lines
    ] ->
      parse_p(remaining_tokens, InsideEscapedString, [
        ["", ..curr_line],
        ..previously_parsed_lines
      ])

    [#(tok, loc), ..], JustParsedNewline, _ ->
      Error(ParseError(
        loc,
        "Expected escaped or non-escaped string after newline, found: " <> token.to_lexeme(
          tok,
        ),
      ))

    // If we're inside an escaped string, we can take anything until we get a double quote,
    // but a double double quote "" escapes the double quote and we keep parsing
    [#(Doublequote, _), #(Doublequote, _), ..remaining_tokens], InsideEscapedString, [
      [str, ..rest_curr_line],
      ..previously_parsed_lines
    ] ->
      parse_p(remaining_tokens, InsideEscapedString, [
        [str <> "\"", ..rest_curr_line],
        ..previously_parsed_lines
      ])

    [#(Doublequote, _), ..remaining_tokens], InsideEscapedString, llf ->
      parse_p(remaining_tokens, JustParsedField, llf)

    [#(other_token, _), ..remaining_tokens], InsideEscapedString, [
      [str, ..rest_curr_line],
      ..previously_parsed_lines
    ] ->
      parse_p(remaining_tokens, InsideEscapedString, [
        [str <> token.to_lexeme(other_token), ..rest_curr_line],
        ..previously_parsed_lines
      ])

    // Anything else is an error
    [#(tok, loc), ..], _, _ ->
      Error(ParseError(loc, "Unexpected token: " <> token.to_lexeme(tok)))
  }
}
