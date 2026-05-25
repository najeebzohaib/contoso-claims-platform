variable "log_analytics_workspace_id" {
  type = string
}
variable "log_analytics_workspace_name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
