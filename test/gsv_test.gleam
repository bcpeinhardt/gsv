import gleeunit
import gleeunit/should
import internal/token.{CR, Comma, Doublequote, LF, Textdata, scan}
import internal/ast.{parse}
import gsv

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

pub fn last_line_has_optional_line_ending() {
  "test\ntest\rtest\r\ntest\n"
  |> gsv.to_lists
  |> should.equal(Ok([["test"], ["test"], ["test"], ["test"]]))
}
