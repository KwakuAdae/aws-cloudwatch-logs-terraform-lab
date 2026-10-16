variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for every resource name"
  type        = string
  default     = "cwlogs-lab"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.project_name))
    error_message = "project_name must be 3-25 characters: lowercase letters, numbers and hyphens."
  }
}

variable "alert_email" {
  description = "Email address for alarm notifications (leave empty to skip the email subscription)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "How long CloudWatch Logs keeps the log events"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs supports (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}

variable "schedule_enabled" {
  description = "Invoke the log generator every minute"
  type        = bool
  default     = true
}

variable "error_rate" {
  description = "Fraction of simulated requests that fail (0.0 - 1.0)"
  type        = number
  default     = 0.05

  validation {
    condition     = var.error_rate >= 0 && var.error_rate <= 1
    error_message = "error_rate must be between 0 and 1."
  }
}

variable "error_alarm_threshold" {
  description = "Alarm when more than this many errors are logged in 5 minutes"
  type        = number
  default     = 10
}

variable "latency_alarm_threshold_ms" {
  description = "Alarm when average latency over 5 minutes exceeds this many milliseconds"
  type        = number
  default     = 500
}
