variable "name_prefix_compact" { type = string }
variable "name_suffix"         { type = string }
variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "log_analytics_workspace_id" {
  type    = string
  default = null
}
variable "containers" {
  type    = list(string)
  default = ["bronze", "silver", "gold"]
}
variable "tags" {
  type    = map(string)
  default = {}
}
