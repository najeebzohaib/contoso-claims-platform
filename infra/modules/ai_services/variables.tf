variable "name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "location" {
  type = string
}
variable "name_suffix" {
  type = string
}
variable "kind" {
  type        = string
  description = "OpenAI or FormRecognizer"
  default     = "OpenAI"
}
variable "sku" {
  type    = string
  default = "S0"
}
variable "public_network_access_enabled" {
  type    = bool
  default = false
}
variable "log_analytics_workspace_id" {
  type    = string
  default = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
