/*
Description:

  Output from sap_deployer module.
*/

output "deployer_id" {
  sensitive = true
  value     = module.sap_deployer.deployer_id
}

output "vnet_mgmt" {
  sensitive = true
  value     = module.sap_deployer.vnet_mgmt
}

output "subnet_mgmt" {
  sensitive = true
  value     = module.sap_deployer.subnet_mgmt
}

output "nsg_mgmt" {
  sensitive = true
  value     = module.sap_deployer.nsg_mgmt
}

output "deployer_uai" {
  sensitive = true
  value     = module.sap_deployer.deployer_uai
}

output "deployer" {
  sensitive = true
  value     = module.sap_deployer.deployers
}

// Comment out code with users.object_id for the time being.
/*
output "deployer_user" {
  sensitive = true
  value = module.sap_deployer.deployer_user
}
*/

output "deployer_kv_user_arm_id" {
  sensitive = true
  value     = module.sap_deployer.deployer_kv_user_arm_id
}

output "deployer_kv_prvt_name" {
  value     = module.sap_deployer.prvt_vault_name
}

output "deployer_kv_user_name" {
  value     = module.sap_deployer.user_vault_name
}
