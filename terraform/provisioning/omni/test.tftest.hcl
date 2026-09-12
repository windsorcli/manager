mock_provider "random" {}

run "generates_a_uuid" {
  command = plan

  assert {
    condition     = random_uuid.account != null
    error_message = "Must generate a random_uuid resource."
  }
}
