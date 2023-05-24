import gleeunit
import gleeunit/should
import token.{CR, Comma, Doublequote, LF, Textdata, scan}
import ast.{parse}
import csv

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
  |> csv.to_lists
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
  |> csv.to_lists
  |> should.equal(Ok([["test"], ["test"], ["test"], ["test"]]))
}

pub fn parse_lfcr_fails_test() {
  "test\n\r"
  |> csv.to_lists
  |> should.equal(Error(Nil))
}

pub fn last_line_has_optional_line_ending() {
  "test\ntest\rtest\r\ntest\n"
  |> csv.to_lists
  |> should.equal(Ok([["test"], ["test"], ["test"], ["test"]]))
}
