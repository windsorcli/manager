mock_provider "aws" {}

variables {
  access_key = "test-access-key"
  secret_key = "test-secret-key"
}

run "endpoint_follows_location" {
  command = plan

  variables {
    location = "hel1"
    buckets  = ["windsor-test-image-factory"]
  }

  assert {
    condition     = output.endpoint == "https://hel1.your-objectstorage.com"
    error_message = "The endpoint must be derived from the location."
  }

  assert {
    condition     = output.region == "hel1"
    error_message = "The region must be the location name."
  }
}

run "rejects_location_without_object_storage" {
  command = plan

  variables {
    location = "ash"
  }

  expect_failures = [var.location]
}

run "rejects_invalid_bucket_name" {
  command = plan

  variables {
    buckets = ["Not_A_Valid_Bucket"]
  }

  expect_failures = [var.buckets]
}

run "buckets_are_destroyable_by_default" {
  command = plan

  variables {
    location = "fsn1"
    buckets  = ["windsor-test-image-factory"]
  }

  assert {
    condition     = alltrue([for b in aws_s3_bucket.this : b.force_destroy])
    error_message = "Buckets must be destroyable without emptying them first."
  }
}
