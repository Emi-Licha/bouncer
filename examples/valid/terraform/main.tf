terraform {
  required_version = ">= 1.0"
}

variable "name" {
  description = "Name the module echoes back"
  type        = string
}

output "name" {
  description = "The name it was given"
  value       = var.name
}
