mock_provider "random" {}

run "defaults_to_32_alphanumeric_characters" {
  command = plan

  assert {
    condition     = random_password.password.length == 32
    error_message = "The default length must be 32."
  }

  assert {
    condition     = random_password.password.special == false
    error_message = "The password must not contain special characters."
  }

  assert {
    condition = (
      random_password.password.min_upper == 1 &&
      random_password.password.min_lower == 1 &&
      random_password.password.min_numeric == 1
    )
    error_message = "The password must contain at least one upper, lower, and numeric character."
  }
}

run "honors_a_custom_length" {
  command = plan

  variables {
    length = 64
  }

  assert {
    condition     = random_password.password.length == 64
    error_message = "The length must follow the length variable."
  }
}

run "rejects_a_short_length" {
  command = plan

  variables {
    length = 8
  }

  expect_failures = [var.length]
}
