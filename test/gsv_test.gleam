import gleam/dict
import gleam/string
import gleeunit
import gsv.{type LineEnding, Unix, Windows}

pub fn main() {
  gleeunit.main()
}

// --- LISTS PARSING -----------------------------------------------------------

pub fn csv_parse_test() {
  let assert Ok(value) =
    gsv.to_lists(
      "Ben,25,true
Austin,25,false",
      separator: ",",
    )
  assert value == [["Ben", "25", "true"], ["Austin", "25", "false"]]
}

pub fn csv_with_crlf_test() {
  let assert Ok(value) =
    gsv.to_lists(
      "Ben\t25\ttrue\r
Austin\t25\tfalse",
      separator: "\t",
    )
  assert value == [["Ben", "25", "true"], ["Austin", "25", "false"]]
}

pub fn csv_with_custom_sep_test() {
  let assert Ok(value) =
    gsv.to_lists(
      "One|Two|Three
1|2|3",
      separator: "|",
    )
  assert value == [["One", "Two", "Three"], ["1", "2", "3"]]
}

pub fn csv_with_long_custom_sep_test() {
  let assert Ok(value) =
    gsv.to_lists(
      "One//Two//Three
1//2//3",
      separator: "//",
    )
  assert value == [["One", "Two", "Three"], ["1", "2", "3"]]
}

pub fn csv_with_weird_custom_sep_test() {
  let assert Ok(value) =
    gsv.to_lists(
      "A-|-B-|-C-|-D
a-|-b-|-c-|-d",
      separator: "-|-",
    )
  assert value == [["A", "B", "C", "D"], ["a", "b", "c", "d"]]
}

pub fn csv_with_mixed_newline_kinds_test() {
  assert gsv.to_lists(
      "one
two\r
three",
      separator: ",",
    )
    == Ok([["one"], ["two"], ["three"]])
}

pub fn whitespace_is_not_trimmed_from_fields_test() {
  let assert Ok(value) =
    gsv.to_lists(
      "Ben , 25 , true
Austin , 25 , false",
      separator: ",",
    )
  assert value == [["Ben ", " 25 ", " true"], ["Austin ", " 25 ", " false"]]
}

pub fn empty_lines_are_ignored_test() {
  let assert Ok(value) =
    gsv.to_lists(
      "
one

two\r
\r
three",
      separator: ",",
    )
  assert value == [["one"], ["two"], ["three"]]
}

pub fn last_line_can_end_with_newline_test() {
  let assert Ok(value) = gsv.to_lists("one\ntwo\n", separator: "|")
  assert value == [["one"], ["two"]]
}

pub fn empty_fields_test() {
  let assert Ok(value) = gsv.to_lists("one||three", separator: "|")
  assert value == [["one", "", "three"]]
}

pub fn csv_ending_with_an_empty_field_test() {
  let assert Ok(value) = gsv.to_lists("one,two,", separator: ",")
  assert value == [["one", "two", ""]]
}

pub fn csv_starting_with_an_empty_field_test() {
  let assert Ok(value) = gsv.to_lists(",two,three", separator: ",")
  assert value == [["", "two", "three"]]
}

pub fn escaped_field_test() {
  let assert Ok(value) =
    "'gleam','functional'
'erlang','functional'"
    // Writing and escaping the double quotes by hand is a bit noisy and makes it
    // hard to read the literal string so I prefer to write single quotes
    // and replace those before parsing :P
    |> string.replace(each: "'", with: "\"")
    |> gsv.to_lists(separator: ",")
  assert value == [["gleam", "functional"], ["erlang", "functional"]]
}

pub fn escaped_field_with_newlines_test() {
  let assert Ok(value) =
    "'wibble
wobble','wibble'"
    |> string.replace(each: "'", with: "\"")
    |> gsv.to_lists(separator: ",")
  assert value == [["wibble\nwobble", "wibble"]]
}

pub fn escaped_field_with_crlf_test() {
  let assert Ok(value) =
    "'wibble\r
wobble','wibble'"
    |> string.replace(each: "'", with: "\"")
    |> gsv.to_lists(separator: ",")
  assert value == [["wibble\r\nwobble", "wibble"]]
}

pub fn escaped_field_with_comma_test() {
  let assert Ok(value) =
    "'wibble,wobble','wibble'"
    |> string.replace(each: "'", with: "\"")
    |> gsv.to_lists(separator: ",")
  assert value == [["wibble,wobble", "wibble"]]
}

pub fn escaped_field_with_escaped_double_quotes_test() {
  let assert Ok(value) =
    "'escaped double quote -> '''"
    |> string.replace(each: "'", with: "\"")
    |> gsv.to_lists(separator: ",")
  assert value == [["escaped double quote -> \""]]
}

pub fn rows_with_different_number_of_fields_test() {
  let assert Ok(value) =
    gsv.to_lists(
      "three,fields,woo
only,two",
      separator: ",",
    )
  assert value == [["three", "fields", "woo"], ["only", "two"]]
}

// --- DICT PARSING ------------------------------------------------------------

pub fn headers_test() {
  let assert Ok(value) =
    gsv.to_dicts(
      "name,age
Ben,27,TRUE,Hello
Austin,27,",
      separator: ",",
    )
  assert value
    == [
      dict.from_list([#("name", "Ben"), #("age", "27")]),
      dict.from_list([#("name", "Austin"), #("age", "27")]),
    ]
}

pub fn dicts_with_empty_str_header_test() {
  let assert Ok(value) =
    gsv.to_dicts(
      "name,\"  \",   ,,age
Ben,wibble,wobble,woo,27,extra_data",
      separator: ",",
    )
  assert value
    == [
      dict.from_list([
        #("name", "Ben"),
        #("  ", "wibble"),
        #("   ", "wobble"),
        #("", "woo"),
        #("age", "27"),
      ]),
    ]
}

pub fn dicts_with_empty_values_test() {
  let assert Ok(value) =
    gsv.to_dicts(
      "name,age
Ben,,,,
Austin,27",
      separator: ",",
    )
  assert value
    == [
      dict.from_list([#("name", "Ben")]),
      dict.from_list([#("name", "Austin"), #("age", "27")]),
    ]
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
  assert gsv.from_dicts(data, ",", gsv.Unix)
    == "colour,name,score,youtube\nPink,Lucy,100,\n,Isaac,99,@IsaacHarrisHolt\n"
}

pub fn quotes_test() {
  let stringy =
    "\"Date\",\"Type\",\"Price\",\"Ammount\"\n\"11/11/2024\",\"Apples\",\"7\",\"5\""

  let assert Ok(value) = gsv.to_lists(stringy, separator: ",")
  assert value
    == [
      ["Date", "Type", "Price", "Ammount"],
      ["11/11/2024", "Apples", "7", "5"],
    ]
}

// --- TESTING ERRORS ----------------------------------------------------------

pub fn double_quote_in_middle_of_field_test() {
  assert Error(gsv.UnescapedQuote(1))
    == "field,other\"field"
    |> gsv.to_lists(",")

  assert Error(gsv.UnescapedQuote(2))
    == "first_line\nfield,other\"field"
    |> gsv.to_lists(",")
}

pub fn unescaped_double_quote_in_escaped_field_test() {
  assert Error(gsv.UnescapedQuote(1))
    == "'unescaped double quote -> ' in escaped field'"
    |> string.replace(each: "'", with: "\"")
    |> gsv.to_lists(",")

  assert Error(gsv.UnescapedQuote(2))
    == "'first escaped'' line'\n'unescaped double quote -> ' in escaped field'"
    |> string.replace(each: "'", with: "\"")
    |> gsv.to_lists(",")
}

pub fn unclosed_escaped_field_test() {
  assert Error(gsv.MissingClosingQuote(1))
    == "'closed','unclosed"
    |> string.replace(each: "'", with: "\"")
    |> gsv.to_lists(",")

  assert Error(gsv.MissingClosingQuote(3))
    == "'first escaped'' line'\nsecond,line,\n'closed','unclosed"
    |> string.replace(each: "'", with: "\"")
    |> gsv.to_lists(",")
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
    |> gsv.to_lists(separator: ",")

  assert rows
    |> gsv.from_lists(separator: ",", line_ending: Windows)
    |> string.replace(each: "\"", with: "'")
    == "Ben, 25,' TRUE\n\r'' '\r
Austin, 25, FALSE\r\n"
}

pub fn dicts_round_trip_test() {
  let assert Ok(dicts) =
    "name,age
Ben,27,TRUE,Hello
Austin,27,"
    |> gsv.to_dicts(separator: ",")

  assert gsv.from_dicts(dicts, ",", Unix) == "age,name
27,Ben
27,Austin\n"
}

// --- TEST HELPERS ------------------------------------------------------------

fn test_lists_roundtrip(
  input: String,
  separator: String,
  line_ending: LineEnding,
) -> Nil {
  let assert Ok(parsed) = gsv.to_lists(input, separator: ",")
  let encoded = gsv.from_lists(parsed, separator, line_ending)
  case input |> string.ends_with("\n") {
    True -> {
      assert encoded == input
    }
    False -> {
      assert encoded == input <> "\n"
    }
  }
}
