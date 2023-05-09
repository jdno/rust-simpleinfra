variable "services" {
  description = "List of ids of Fastly services"
  type        = list(string)
  default     = []
}
