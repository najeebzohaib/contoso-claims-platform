variable "location" {
  type    = string
  default = "uksouth"
}
variable "owner_email" {
  type = string
}
variable "maintainer_email" {
  type = string
}
variable "github_repo" {
  type    = string
  default = "najeebzohaib/contoso-claims-platform"
}
variable "log_analytics_retention_days" {
  type    = number
  default = 90
}
variable "name_suffix" {
  type = string
}
variable "tenant_admin_object_id" {
  type = string
}
variable "my_public_ip" {
  type    = string
  default = "0.0.0.0/0"
}
