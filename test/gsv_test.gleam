import birdie
import gleam/dict
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import gsv.{type LineEnding, Unix, Windows}

pub fn main() {
  gleeunit.main()
}

// --- LISTS PARSING -----------------------------------------------------------

pub fn csv_parse_test() {
  "Ben,25,true
Austin,25,false"
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["Ben", "25", "true"], ["Austin", "25", "false"]])
}

pub fn csv_with_crlf_test() {
  "Ben,25,true\r
Austin,25,false"
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["Ben", "25", "true"], ["Austin", "25", "false"]])
}

pub fn csv_with_mixed_newline_kinds_test() {
  "one
two\r
three"
  |> gsv.to_lists
  |> should.equal(Ok([["one"], ["two"], ["three"]]))
}

pub fn whitespace_is_not_trimmed_from_fields_test() {
  "Ben , 25 , true
Austin , 25 , false"
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["Ben ", " 25 ", " true"], ["Austin ", " 25 ", " false"]])
}

pub fn empty_lines_are_ignored_test() {
  "
one

two\r
\r
three"
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["one"], ["two"], ["three"]])
}

pub fn last_line_can_end_with_newline_test() {
  "one\ntwo\n"
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["one"], ["two"]])
}

pub fn empty_fields_test() {
  "one,,three"
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["one", "", "three"]])
}

pub fn csv_ending_with_an_empty_field_test() {
  "one,two,"
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["one", "two", ""]])
}

pub fn csv_starting_with_an_empty_field_test() {
  ",two,three"
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["", "two", "three"]])
}

pub fn escaped_field_test() {
  "'gleam','functional'
'erlang','functional'"
  // Writing and escaping the double quotes by hand is a bit noisy and makes it
  // hard to read the literal string so I prefer to write single quotes
  // and replace those before parsing :P
  |> string.replace(each: "'", with: "\"")
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["gleam", "functional"], ["erlang", "functional"]])
}

pub fn escaped_field_with_newlines_test() {
  "'wibble
wobble','wibble'"
  |> string.replace(each: "'", with: "\"")
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["wibble\nwobble", "wibble"]])
}

pub fn escaped_field_with_crlf_test() {
  "'wibble\r
wobble','wibble'"
  |> string.replace(each: "'", with: "\"")
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["wibble\r\nwobble", "wibble"]])
}

pub fn escaped_field_with_comma_test() {
  "'wibble,wobble','wibble'"
  |> string.replace(each: "'", with: "\"")
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["wibble,wobble", "wibble"]])
}

pub fn escaped_field_with_escaped_double_quotes_test() {
  "'escaped double quote -> '''"
  |> string.replace(each: "'", with: "\"")
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["escaped double quote -> \""]])
}

pub fn rows_with_different_number_of_fields_test() {
  "three,fields,woo
only,two"
  |> gsv.to_lists
  |> should.be_ok
  |> should.equal([["three", "fields", "woo"], ["only", "two"]])
}

// --- DICT PARSING ------------------------------------------------------------

pub fn headers_test() {
  "name,age
Ben,27,TRUE,Hello
Austin,27,"
  |> gsv.to_dicts
  |> should.be_ok
  |> should.equal([
    dict.from_list([#("name", "Ben"), #("age", "27")]),
    dict.from_list([#("name", "Austin"), #("age", "27")]),
  ])
}

pub fn dicts_with_empty_str_header_test() {
  "name,\"  \",   ,,age
Ben,wibble,wobble,woo,27,extra_data"
  |> gsv.to_dicts
  |> should.be_ok
  |> should.equal([
    dict.from_list([
      #("name", "Ben"),
      #("  ", "wibble"),
      #("   ", "wobble"),
      #("", "woo"),
      #("age", "27"),
    ]),
  ])
}

pub fn dicts_with_empty_values_test() {
  "name,age
Ben,,,,
Austin,27"
  |> gsv.to_dicts
  |> should.be_ok
  |> should.equal([
    dict.from_list([#("name", "Ben")]),
    dict.from_list([#("name", "Austin"), #("age", "27")]),
  ])
}

pub fn dicts_with_missing_values_test() {
  let data = [
    dict.from_list([#("name", "Lucy"), #("score", "100"), #("colour", "Pink")]),
    dict.from_list([
      #("name", "Isaac"),
      #("youtube", "@IsaacHarrisHolt"),
      #("score", "99"),
    ]),
  ]
  gsv.from_dicts(data, ",", gsv.Unix)
  |> should.equal(
    "colour,name,score,youtube\nPink,Lucy,100,\n,Isaac,99,@IsaacHarrisHolt\n",
  )
}

pub fn quotes_test() {
  let stringy =
    "\"Date\",\"Type\",\"Price\",\"Ammount\"\n\"11/11/2024\",\"Apples\",\"7\",\"5\""

  gsv.to_lists(stringy)
  |> should.be_ok
  |> should.equal([
    ["Date", "Type", "Price", "Ammount"],
    ["11/11/2024", "Apples", "7", "5"],
  ])
}

// --- TESTING ERRORS ----------------------------------------------------------

pub fn double_quote_in_middle_of_field_test() {
  "field,other\"field"
  |> pretty_print_error
  |> birdie.snap("double quote in middle of field")
}

pub fn unescaped_double_quote_in_escaped_field_test() {
  "'unescaped double quote -> ' in escaped field'"
  |> string.replace(each: "'", with: "\"")
  |> pretty_print_error
  |> birdie.snap("unescaped double quote in escaped field")
}

pub fn unclosed_escaped_field_test() {
  "'closed','unclosed"
  |> string.replace(each: "'", with: "\"")
  |> pretty_print_error
  |> birdie.snap("unclosed escaped field")
}

// --- ENCODING TESTS ----------------------------------------------------------

pub fn encode_test() {
  "Ben, 25
Austin, 21"
  |> test_lists_roundtrip(",", Unix)
}

pub fn encode_with_escaped_string_test() {
  "Ben, 25,' TRUE
\r'' '
Austin, 25, FALSE"
  |> string.replace(each: "'", with: "\"")
  |> test_lists_roundtrip(",", Unix)
}

pub fn encode_with_escaped_string_windows_test() {
  let assert Ok(rows) =
    "Ben, 25,' TRUE\n\r'' '
Austin, 25, FALSE"
    |> string.replace(each: "'", with: "\"")
    |> gsv.to_lists

  rows
  |> gsv.from_lists(separator: ",", line_ending: Windows)
  |> string.replace(each: "\"", with: "'")
  |> should.equal(
    "Ben, 25,' TRUE\n\r'' '\r
Austin, 25, FALSE\r\n",
  )
}

pub fn dicts_round_trip_test() {
  "name,age
Ben,27,TRUE,Hello
Austin,27,"
  |> gsv.to_dicts
  |> should.be_ok
  |> gsv.from_dicts(",", Unix)
  |> should.equal(
    "age,name
27,Ben
27,Austin\n",
  )
}

// --- TEST HELPERS ------------------------------------------------------------

fn test_lists_roundtrip(
  input: String,
  separator: String,
  line_ending: LineEnding,
) -> Nil {
  let assert Ok(parsed) = gsv.to_lists(input)
  let encoded = gsv.from_lists(parsed, separator, line_ending)
  case input |> string.ends_with("\n") {
    True -> encoded |> should.equal(input)
    False -> encoded |> should.equal(input <> "\n")
  }
}

fn pretty_print_error(input: String) -> String {
  let assert Error(error) = gsv.to_lists(input)
  let error_message = error_to_message(error)
  let #(error_line, error_column) =
    error_to_position(error)
    |> position_to_line_and_column(in: input)

  string.replace(in: input, each: "\r\n", with: "\n")
  |> string.split(on: "\n")
  |> list.index_map(fn(line, line_number) {
    case line_number == error_line {
      False -> line
      True -> {
        let padding = string.repeat(" ", error_column)
        let pointer_line = padding <> "┬"
        let message_line = padding <> "╰─ " <> error_message
        line <> "\n" <> pointer_line <> "\n" <> message_line
      }
    }
  })
  |> string.join(with: "\n")
}

fn error_to_position(error: gsv.ParseError) -> Int {
  case error {
    gsv.UnclosedEscapedField(position) | gsv.UnescapedQuote(position) ->
      position
  }
}

fn error_to_message(error: gsv.ParseError) -> String {
  case error {
    gsv.UnclosedEscapedField(_) -> "This escaped field is not closed"
    gsv.UnescapedQuote(_) -> "This is an unescaped double quote"
  }
}

fn position_to_line_and_column(position: Int, in string: String) -> #(Int, Int) {
  do_position_to_line_and_column(string, position, 0, 0)
}

fn do_position_to_line_and_column(
  string: String,
  position: Int,
  line: Int,
  col: Int,
) -> #(Int, Int) {
  case position, string {
    0, _ -> #(line, col)
    _, "" -> panic as "position out of string bounds"
    _, "\n" <> rest ->
      do_position_to_line_and_column(rest, position - 1, line + 1, 0)
    _, "\r\n" <> rest ->
      do_position_to_line_and_column(rest, position - 2, line + 1, 0)
    _, _ -> {
      let rest = drop_bytes(string, 1)
      do_position_to_line_and_column(rest, position - 1, line, col + 1)
    }
  }
}

@external(erlang, "gsv_ffi", "drop_bytes")
@external(javascript, "./gsv_ffi.mjs", "drop_bytes")
fn drop_bytes(string: String, bytes: Int) -> String
