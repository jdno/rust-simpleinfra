terraform {
  source = "../../../modules//datadog-aws"
}

include {
  path           = find_in_parent_folders()
  merge_strategy = "deep"
}

inputs = {
  s3_log_buckets = [
    "rust-crates-io-logs",
    "rust-release-logs",
  ]
}
