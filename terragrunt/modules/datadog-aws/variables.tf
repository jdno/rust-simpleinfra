variable "s3_log_buckets" {
  description = "List of S3 buckets that store logs"
  type        = list(string)
  default     = []
}
