variable "name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "location" {
  type = string
}
variable "publisher_name" {
  type    = string
  default = "Contoso Claims Platform"
}
variable "publisher_email" {
  type = string
}
variable "sku_name" {
  type    = string
  default = "Developer_1"
}
variable "subnet_id" {
  type = string
}
variable "log_analytics_workspace_id" {
  type    = string
  default = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
