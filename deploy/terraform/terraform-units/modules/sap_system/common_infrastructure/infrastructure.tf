##################################################################################################################
# RESOURCES
##################################################################################################################

# RESOURCE GROUP =================================================================================================

# Creates the resource group
resource "azurerm_resource_group" "resource-group" {
  count    = local.rg_exists ? 0 : 1
  name     = local.rg_name
  location = local.region
}

# Imports data of existing resource group
data "azurerm_resource_group" "resource-group" {
  count = local.rg_exists ? 1 : 0
  name  = split("/", local.rg_arm_id)[4]
}

# VNETs ==========================================================================================================

# Creates the SAP VNET
resource "azurerm_virtual_network" "vnet-sap" {
  count               = local.vnet_sap_exists ? 0 : 1
  name                = local.vnet_sap_name
  location            = local.rg_exists ? data.azurerm_resource_group.resource-group[0].location : azurerm_resource_group.resource-group[0].location
  resource_group_name = local.rg_exists ? data.azurerm_resource_group.resource-group[0].name : azurerm_resource_group.resource-group[0].name
  address_space       = [local.vnet_sap_addr]
}

# Imports data of existing SAP VNET
data "azurerm_virtual_network" "vnet-sap" {
  count               = local.vnet_sap_exists ? 1 : 0
  name                = split("/", local.vnet_sap_arm_id)[8]
  resource_group_name = split("/", local.vnet_sap_arm_id)[4]
}

# STORAGE ACCOUNTS ===============================================================================================

# Generates random text for boot diagnostics storage account name
resource "random_id" "random-id" {
  keepers = {
    # Generate a new id only when a new resource group is defined
    resource_group = local.rg_exists ? data.azurerm_resource_group.resource-group[0].name : azurerm_resource_group.resource-group[0].name
  }
  byte_length = 4
}

# Creates boot diagnostics storage account
resource "azurerm_storage_account" "storage-bootdiag" {
  name                      = "sabootdiag${random_id.random-id.hex}"
  resource_group_name       = local.rg_exists ? data.azurerm_resource_group.resource-group[0].name : azurerm_resource_group.resource-group[0].name
  location                  = local.rg_exists ? data.azurerm_resource_group.resource-group[0].location : azurerm_resource_group.resource-group[0].location
  account_replication_type  = "LRS"
  account_tier              = "Standard"
  enable_https_traffic_only = var.options.enable_secure_transfer == "" ? true : var.options.enable_secure_transfer
}


# PROXIMITY PLACEMENT GROUP ===============================================================================================

resource "azurerm_proximity_placement_group" "ppg" {
  count               = local.ppg_exists ? 0 : 1
  name                = local.ppg_name
  resource_group_name = local.rg_exists ? data.azurerm_resource_group.resource-group[0].name : azurerm_resource_group.resource-group[0].name
  location            = local.rg_exists ? data.azurerm_resource_group.resource-group[0].location : azurerm_resource_group.resource-group[0].location
}


data "azurerm_proximity_placement_group" "ppg" {
  count               = local.ppg_exists ? 1 : 0
  name                = split("/", local.ppg_arm_id)[8]
  resource_group_name = split("/", local.ppg_arm_id)[4]
}
