mock_provider "random" {}

run "admin_password_defaults_to_32_alphanumeric_characters" {
  command = plan

  assert {
    condition     = random_password.admin.length == 32
    error_message = "The default length must be 32."
  }

  assert {
    condition     = random_password.admin.special == false
    error_message = "The password must not contain special characters."
  }

  assert {
    condition = (
      random_password.admin.min_upper == 1 &&
      random_password.admin.min_lower == 1 &&
      random_password.admin.min_numeric == 1
    )
    error_message = "The password must contain at least one upper, lower, and numeric character."
  }
}

run "honors_a_custom_admin_password_length" {
  command = plan

  variables {
    admin_password_length = 64
  }

  assert {
    condition     = random_password.admin.length == 64
    error_message = "The length must follow admin_password_length."
  }
}

run "rejects_a_short_admin_password_length" {
  command = plan

  variables {
    admin_password_length = 8
  }

  expect_failures = [var.admin_password_length]
}
