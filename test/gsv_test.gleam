import gleeunit
import gleeunit/should
import internal/token.{CR, Comma, Doublequote, LF, Textdata, scan}
import internal/ast.{parse}
import gsv
import gleam/list
import gleam/result
import gleam/int
import gleam/string

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
  |> parse
  |> should.equal(Ok([
    ["Ben", " 25", " TRUE\n\r\""],
    ["Austin", " 25", " FALSE"],
  ]))
}

pub fn parse_empty_string_fail_test() {
  ""
  |> scan
  |> parse
  |> should.equal(Error(Nil))
}

pub fn csv_parse_test() {
  "Ben, 25,\" TRUE\n\r\"\"\"\nAustin, 25, FALSE"
  |> gsv.to_lists
  |> should.equal(Ok([
    ["Ben", " 25", " TRUE\n\r\""],
    ["Austin", " 25", " FALSE"],
  ]))
}

pub fn scan_crlf_test() {
  "\r\n"
  |> scan
  |> should.equal([CR, LF])
}

pub fn parse_crlf_test() {
  "test\ntest\rtest\r\ntest"
  |> gsv.to_lists
  |> should.equal(Ok([["test"], ["test"], ["test"], ["test"]]))
}

pub fn parse_lfcr_fails_test() {
  "test\n\r"
  |> gsv.to_lists
  |> should.equal(Error(Nil))
}

pub fn last_line_has_optional_line_ending_test() {
  "test\ntest\rtest\r\ntest\n"
  |> gsv.to_lists
  |> should.equal(Ok([["test"], ["test"], ["test"], ["test"]]))
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
  |> gsv.from_lists(delimiter: ",", line_ending: "\n")
  |> should.equal("Ben, 25\nAustin, 21")
}
