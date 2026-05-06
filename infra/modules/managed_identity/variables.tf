variable "name" {
  description = "Logical name (suffix added to 'id-' prefix)"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the identity in"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
