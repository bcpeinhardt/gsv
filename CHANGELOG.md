# Changelog

## Unreleased

## v1.4.0 - 29 March 2024
- Fix bug where trailing comma was causing error

## v1.3.1 - 1 February 2024
- Update to gleam_stdlib = "~> 0.34 or ~> 1.0" in preparation for 1.0

## v1.2.1 - 5 January 2024
- Fix bug with double commas producing error, now produce empty string

## v1.2.0 - 29 December 2023
- Add `to_lists_or_error` function

## v1.1.0 - 29 December 2023
- Add a function which panics with an appropriate error message on failure to 
  parse csv. This includes the token location.

## v1.0.0 - 27 December 2023
- Init changelog w/v1 so people's stuff doesn't break.