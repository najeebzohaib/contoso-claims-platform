variable "github_org" { type = string }
variable "github_repo" { type = string }
variable "tfstate_storage_account_id" {
  type        = string
  description = "Full resource ID of the bootstrap state storage account"
}

variable "tags" {
  type = map(string)
  default = {
    Project   = "ContosoClaimsLearning"
    ManagedBy = "Terraform"
    Workload  = "claims-platform-cicd"
  }
}
