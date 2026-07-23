variable "region" {
  description = "AWS region hosting the buckets."
  type        = string
  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "The region must be an AWS region name, e.g. us-east-1."
  }
}

variable "buckets" {
  description = "Bucket names to create. S3 bucket names are globally unique, so they need a context-unique prefix."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for b in var.buckets : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", b))])
    error_message = "Bucket names must be 3-63 characters of lowercase alphanumerics, dots, or hyphens, starting and ending alphanumeric."
  }
}

variable "versioning" {
  description = "Keep object versions. Off by default: a cache of rebuildable artifacts does not need history, and versions accrue cost."
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Delete remaining objects, including all noncurrent versions, when the bucket is destroyed. On by default: these buckets hold rebuildable artifacts, and a non-empty or versioned bucket otherwise blocks teardown."
  type        = bool
  default     = true
}

variable "context_id" {
  description = "Context ID for the resources"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to resources (default is empty)."
  type        = map(string)
  default     = {}
}
