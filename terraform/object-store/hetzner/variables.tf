variable "access_key" {
  description = "S3 access key for the Hetzner project. Generated in the Hetzner console; there is no API to create one."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.access_key) > 0
    error_message = "The access key must not be empty."
  }
}

variable "secret_key" {
  description = "S3 secret key paired with access_key."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.secret_key) > 0
    error_message = "The secret key must not be empty."
  }
}

variable "location" {
  description = "Hetzner location hosting the buckets. Object Storage runs in fsn1, nbg1, and hel1 only, not in the ash, hil, or sin compute locations."
  type        = string
  default     = "fsn1"
  validation {
    condition     = contains(["fsn1", "nbg1", "hel1"], var.location)
    error_message = "Hetzner Object Storage is available in fsn1, nbg1, and hel1 only."
  }
}

variable "buckets" {
  description = "Bucket names to create. Names are shared across the whole Hetzner project, so they need a context-unique prefix."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for b in var.buckets : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", b))])
    error_message = "Bucket names must be 3-63 characters of lowercase alphanumerics, dots, or hyphens, starting and ending alphanumeric."
  }
}

variable "force_destroy" {
  description = "Delete remaining objects when the bucket is destroyed. On by default: these buckets hold rebuildable artifacts, and a non-empty bucket otherwise blocks teardown."
  type        = bool
  default     = true
}
