import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should
import gsv.{Unix, Windows}
import gsv/internal/ast.{ParseError, parse}
import gsv/internal/token.{
  CR, Comma, Doublequote, LF, Location, Textdata, scan, with_location,
}

pub fn main() {
  gleeunit.main()
}

pub fn scan_test() {
  "Ben, 25,\" TRUE\r\n\""
  |> scan
  |> should.equal([
    Textdata("Ben"),
    Comma,
    Textdata(" 25"),
    Comma,
    Doublequote,
    Textdata(" TRUE"),
    CR,
    LF,
    Doublequote,
  ])
}

pub fn parse_test() {
  "Ben, 25,\" TRUE\n\r\"\"\"\nAustin, 25, FALSE"
  |> scan
  |> with_location
  |> parse
  |> should.equal(Ok([["Ben", "25", " TRUE\n\r\""], ["Austin", "25", "FALSE"]]))
}

pub fn parse_empty_string_fail_test() {
  ""
  |> scan
  |> with_location
  |> parse
  |> result.nil_error
  |> should.equal(Error(Nil))
}

pub fn csv_parse_test() {
  "Ben, 25,\" TRUE\n\r\"\"\"\nAustin, 25, FALSE"
  |> gsv.to_lists
  |> should.equal(Ok([["Ben", "25", " TRUE\n\r\""], ["Austin", "25", "FALSE"]]))
}

pub fn scan_crlf_test() {
  "\r\n"
  |> scan
  |> should.equal([CR, LF])
}

pub fn parse_crlf_test() {
  "test\ntest\r\ntest"
  |> gsv.to_lists
  |> should.equal(Ok([["test"], ["test"], ["test"]]))
}

pub fn parse_lfcr_fails_test() {
  "test\n\r"
  |> gsv.to_lists
  |> should.be_error
}

pub fn last_line_has_optional_line_ending_test() {
  "test\ntest\r\ntest\n"
  |> gsv.to_lists
  |> should.equal(Ok([["test"], ["test"], ["test"]]))
}

// ---------- Example doing CSV string -> Custom type ------------------------
pub type User {
  User(name: String, age: Int)
}

fn from_list(record: List(String)) -> Result(User, Nil) {
  use name <- result.try(list.at(record, 0))
  use age_str <- result.try(list.at(record, 1))
  use age <- result.try(int.parse(string.trim(age_str)))
  Ok(User(name, age))
}

pub fn decode_to_type_test() {
  let assert Ok(lls) =
    "Ben, 25\nAustin, 21"
    |> gsv.to_lists
  let users =
    list.fold(lls, [], fn(acc, record) { [from_list(record), ..acc] })
    |> list.reverse

  users
  |> should.equal([Ok(User("Ben", 25)), Ok(User("Austin", 21))])
}

// ---------------------------------------------------------------------------

pub fn encode_test() {
  let assert Ok(lls) = gsv.to_lists("Ben, 25\nAustin, 21")
  lls
  |> gsv.from_lists(separator: ",", line_ending: Unix)
  |> should.equal("Ben,25\nAustin,21")
}

pub fn encode_with_escaped_string_test() {
  let assert Ok(lls) =
    "Ben, 25,\" TRUE\n\r\"\" \"\nAustin, 25, FALSE"
    |> gsv.to_lists

  lls
  |> gsv.from_lists(separator: ",", line_ending: Unix)
  |> should.equal("Ben,25,\" TRUE\n\r\"\" \"\nAustin,25,FALSE")
}

pub fn encode_with_escaped_string_windows_test() {
  let assert Ok(lls) =
    "Ben, 25,\" TRUE\n\r\"\" \"\nAustin, 25, FALSE"
    |> gsv.to_lists

  lls
  |> gsv.from_lists(separator: ",", line_ending: Windows)
  |> should.equal("Ben,25,\" TRUE\n\r\"\" \"\r\nAustin,25,FALSE")
}

pub fn for_the_readme_test() {
  let csv_str = "Hello, World\nGoodbye, Mars"

  // Parse a CSV string to a List(List(String))
  let assert Ok(records) = gsv.to_lists(csv_str)

  // Write a List(List(String)) to a CSV string
  records
  |> gsv.from_lists(separator: ",", line_ending: Windows)
  |> should.equal("Hello,World\r\nGoodbye,Mars")
}

pub fn error_cases_test() {
  let produce_error = fn(csv_str) {
    case
      csv_str
      |> scan
      |> with_location
      |> parse
    {
      Ok(_) -> panic as "Expected an error"
      Error(ParseError(loc, msg)) -> #(loc, msg)
    }
  }

  produce_error("Ben, 25,\n, TRUE")
  |> should.equal(#(
    Location(2, 1),
    "Expected escaped or non-escaped string after newline, found: ,",
  ))
  produce_error("Austin, 25, FALSE\n\"Ben Peinhardt\", 25,\n, TRUE")
  |> should.equal(#(
    Location(3, 1),
    "Expected escaped or non-escaped string after newline, found: ,",
  ))
}

// pub fn totally_panics_test() {
//   "Ben, 25,, TRUE" |> gsv.to_lists_or_panic
// }

pub fn totally_doesnt_error_test() {
  "Ben, 25,, TRUE"
  |> gsv.to_lists
  |> should.equal(Ok([["Ben", "25", "", "TRUE"]]))
}

pub fn trailing_commas_fine_test() {
  "Ben, 25, TRUE, Hello\nAustin, 25,\n"
  |> gsv.to_lists
  |> should.equal(Ok([["Ben", "25", "TRUE", "Hello"], ["Austin", "25", ""]]))
}

pub fn headers_test() {
  "name, age\nBen, 27, TRUE, Hello\nAustin, 27,\n"
  |> gsv.to_dicts
  |> should.be_ok
  |> should.equal([
    dict.from_list([#("name", "Ben"), #("age", "27")]),
    dict.from_list([#("name", "Austin"), #("age", "27")]),
  ])
}

pub fn dicts_round_trip_test() {
  "name, age\nBen, 27, TRUE, Hello\nAustin, 27,\n"
  |> gsv.to_dicts
  |> should.be_ok
  |> gsv.from_dicts(",", Unix)
  |> should.equal("age,name\n27,Ben\n27,Austin")
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
