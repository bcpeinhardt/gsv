import gleeunit
import gleeunit/should
import token.{CR, Comma, Doublequote, Newline, Textdata, scan}
import ast.{parse}
import csv

pub fn main() {
  gleeunit.main()
}

pub fn scan_test() {
  "Ben, 25,\" TRUE\n\r\""
  |> scan
  |> should.equal([
    Textdata("Ben"),
    Comma,
    Textdata(" 25"),
    Comma,
    Doublequote,
    Textdata(" TRUE"),
    Newline,
    CR,
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
  |> csv.csv_to_lists
  |> should.equal(Ok([
    ["Ben", " 25", " TRUE\n\r\""],
    ["Austin", " 25", " FALSE"],
  ]))
}
