variable "support_to_email" {
  description = "Inbox that should receive support tickets."
  type        = string
}

variable "support_from_email" {
  description = "Sender address for outgoing ticket emails. Must be verified in SES — this config creates the SES identity, but you still have to click the verification link SES emails to this address (or, for a domain identity, add the DNS records SES gives you) before sends will actually succeed."
  type        = string
}

variable "allowed_origin" {
  description = "The site's origin the Lambda accepts requests from (CORS). Exact match, not a wildcard, since this endpoint accepts writes. Update this and re-apply once you move off the github.io URL onto latefeetracker.app."
  type        = string
  default     = "https://kylesmart2.github.io"
}

variable "function_name" {
  description = "Name for the Lambda function."
  type        = string
  default     = "late-fee-support-form"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the function's log group."
  type        = number
  default     = 14
}
