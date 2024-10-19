import gleam/dict
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

// --- DICT PARSING ------------------------------------------------------------

pub fn headers_test() {
  "name, age\nBen, 27, TRUE, Hello\nAustin, 27,\n"
  |> gsv.to_dicts
  |> should.be_ok
  |> should.equal([
    dict.from_list([#("name", "Ben"), #("age", "27")]),
    dict.from_list([#("name", "Austin"), #("age", "27")]),
  ])
}

pub fn dicts_with_empty_str_header_test() {
  "name,\"  \",   ,,age\nBen,foo,bar,baz,27,extra_data"
  |> gsv.to_dicts
  |> should.be_ok
  |> gsv.from_dicts(",", Unix)
  |> should.equal("age,name\n27,Ben")
}

pub fn dicts_with_empty_values_test() {
  "name, age\nBen,,,,\nAustin, 27"
  |> gsv.to_dicts
  |> should.be_ok
  |> should.equal([
    dict.from_list([#("name", "Ben")]),
    dict.from_list([#("age", "27"), #("name", "Austin")]),
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
    "colour,name,score,youtube\nPink,Lucy,100,\n,Isaac,99,@IsaacHarrisHolt",
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
  |> gsv.to_lists
  |> should.be_error
  |> should.equal(todo)
}

pub fn unescaped_double_quote_in_escaped_field_test() {
  "'unescaped double quote -> ' in escaped field'"
  |> string.replace(each: "'", with: "\"")
  |> gsv.to_lists
  |> should.be_error
  |> should.equal(todo)
}

pub fn unescaped_carriage_return_test() {
  todo as "decide what to do"
  "test\n\r"
  |> gsv.to_lists
  |> should.be_error
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
  let assert Ok(lls) =
    "Ben, 25,\" TRUE\n\r\"\" \"\nAustin, 25, FALSE"
    |> gsv.to_lists

  lls
  |> gsv.from_lists(separator: ",", line_ending: Windows)
  |> should.equal("Ben,25,\" TRUE\n\r\"\" \"\r\nAustin,25,FALSE")
}

pub fn dicts_round_trip_test() {
  "name, age\nBen, 27, TRUE, Hello\nAustin, 27,\n"
  |> gsv.to_dicts
  |> should.be_ok
  |> gsv.from_dicts(",", Unix)
  |> should.equal("age,name\n27,Ben\n27,Austin")
}

// --- TEST HELPERS ------------------------------------------------------------

fn test_lists_roundtrip(
  input: String,
  separator: String,
  line_ending: LineEnding,
) -> Nil {
  let assert Ok(parsed) = gsv.to_lists(input)
  let encoded = gsv.from_lists(parsed, separator, line_ending)
  encoded |> should.equal(input)
}
