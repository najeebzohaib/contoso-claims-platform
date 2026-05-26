variable "name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "location" {
  type = string
}
variable "subnet_id" {
  type = string
}
variable "backend_fqdn" {
  type    = string
  default = "placeholder.internal"
}
variable "log_analytics_workspace_id" {
  type    = string
  default = null
}
variable "tags" {
  type    = map(string)
  default = {}
}

variable "backend_host_header" {
  type        = string
  default     = ""
  description = "Host header to send to backend."
}
