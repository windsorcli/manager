mock_provider "aws" {}

run "endpoint_follows_region" {
  command = plan

  variables {
    region     = "eu-central-1"
    buckets    = ["windsor-test-image-factory"]
    context_id = "wtest123"
    tags       = { Team = "platform" }
  }

  assert {
    condition     = output.endpoint == "https://s3.eu-central-1.amazonaws.com"
    error_message = "The endpoint must be derived from the region."
  }
}

run "rejects_invalid_region" {
  command = plan

  variables {
    region = "frankfurt"
  }

  expect_failures = [var.region]
}

run "buckets_are_destroyable_by_default" {
  command = plan

  variables {
    region  = "eu-central-1"
    buckets = ["windsor-test-image-factory"]
  }

  assert {
    condition     = alltrue([for b in aws_s3_bucket.this : b.force_destroy])
    error_message = "Buckets must be destroyable without emptying them first."
  }
}
