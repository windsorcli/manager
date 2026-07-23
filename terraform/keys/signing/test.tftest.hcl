mock_provider "tls" {}

run "defaults_to_ecdsa_p256" {
  command = plan

  assert {
    condition     = tls_private_key.signing.algorithm == "ECDSA"
    error_message = "The default algorithm must be ECDSA."
  }

  assert {
    condition     = tls_private_key.signing.ecdsa_curve == "P256"
    error_message = "The default curve must be P256."
  }
}

run "rejects_unknown_curve" {
  command = plan

  variables {
    ecdsa_curve = "P128"
  }

  expect_failures = [var.ecdsa_curve]
}
