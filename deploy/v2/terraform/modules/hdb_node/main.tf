##################################################################################################################
# HANA DB Node
##################################################################################################################

# NETWORK SECURITY RULES =========================================================================================

# Creates network security rule to deny external traffic for SAP admin subnet
resource "azurerm_network_security_rule" "nsr-admin" {
  count                       = var.infrastructure.vnets.sap.subnet_admin.nsg.is_existing ? 0 : 1
  name                        = "deny-inbound-traffic"
  resource_group_name         = var.nsg-admin[0].resource_group_name
  network_security_group_name = var.nsg-admin[0].name
  priority                    = 102
  direction                   = "Inbound"
  access                      = "deny"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = var.infrastructure.vnets.sap.subnet_admin.prefix
}

# Creates network security rule for SAP DB subnet
resource "azurerm_network_security_rule" "nsr-db" {
  count                       = var.infrastructure.vnets.sap.subnet_db.nsg.is_existing ? 0 : 1
  name                        = "nsr-subnet-db"
  resource_group_name         = var.nsg-db[0].resource_group_name
  network_security_group_name = var.nsg-db[0].name
  priority                    = 102
  direction                   = "Inbound"
  access                      = "allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.infrastructure.vnets.management.subnet_mgmt.prefix
  destination_address_prefix  = var.infrastructure.vnets.sap.subnet_db.prefix
}

# NICS ============================================================================================================

# Creates the admin traffic NIC and private IP address for database nodes
resource "azurerm_network_interface" "nics-dbnodes-admin" {
  for_each                      = local.dbnodes
  name                          = "${each.value.name}-admin-nic"
  location                      = var.resource-group[0].location
  resource_group_name           = var.resource-group[0].name
  network_security_group_id     = var.nsg-admin[0].id
  enable_accelerated_networking = true

  ip_configuration {
    name                          = "${each.value.name}-admin-nic-ip"
    subnet_id                     = var.subnet-sap-admin[0].id
    private_ip_address            = var.infrastructure.vnets.sap.subnet_admin.is_existing ? each.value.admin_nic_ip : lookup(each.value, "admin_nic_ip", false) != false ? each.value.admin_nic_ip : cidrhost(var.infrastructure.vnets.sap.subnet_admin.prefix, tonumber(each.key) + 4)
    private_ip_address_allocation = "static"
  }
}

# Creates the DB traffic NIC and private IP address for database nodes
resource "azurerm_network_interface" "nics-dbnodes-db" {
  for_each                      = local.dbnodes
  name                          = "${each.value.name}-db-nic"
  location                      = var.resource-group[0].location
  resource_group_name           = var.resource-group[0].name
  network_security_group_id     = var.nsg-db[0].id
  enable_accelerated_networking = true

  ip_configuration {
    primary                       = true
    name                          = "${each.value.name}-db-nic-ip"
    subnet_id                     = var.subnet-sap-db[0].id
    private_ip_address            = var.infrastructure.vnets.sap.subnet_db.is_existing ? each.value.db_nic_ip : lookup(each.value, "db_nic_ip", false) != false ? each.value.db_nic_ip : cidrhost(var.infrastructure.vnets.sap.subnet_db.prefix, tonumber(each.key) + 4)
    private_ip_address_allocation = "static"
  }
}

# LOAD BALANCER ===================================================================================================

resource "azurerm_lb" "hana-lb" {
  for_each            = local.loadbalancers
  name                = "hana-${each.value.sid}-lb"
  resource_group_name = var.resource-group[0].name
  location            = var.resource-group[0].location

  frontend_ip_configuration {
    name                          = "hana-${each.value.sid}-lb-feip"
    subnet_id                     = var.subnet-sap-db[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.infrastructure.vnets.sap.subnet_db.is_existing ? each.value.lb_fe_ip : lookup(each.value, "lb_fe_ip", false) != false ? each.value.lb_fe_ip : cidrhost(var.infrastructure.vnets.sap.subnet_db.prefix, tonumber(each.key) + 4 + length(local.dbnodes))
  }
}

resource "azurerm_lb_backend_address_pool" "hana-lb-back-pool" {
  for_each            = local.loadbalancers
  resource_group_name = var.resource-group[0].name
  loadbalancer_id     = azurerm_lb.hana-lb[tonumber(each.key)].id
  name                = "hana-${each.value.sid}-lb-bep"
}

resource "azurerm_lb_probe" "hana-lb-health-probe" {
  for_each            = local.loadbalancers
  resource_group_name = var.resource-group[0].name
  loadbalancer_id     = azurerm_lb.hana-lb[0].id
  name                = "hana-${each.value.sid}-lb-hp"
  port                = "625${each.value.instance_number}"
  protocol            = "Tcp"
  interval_in_seconds = 5
  number_of_probes    = 2
}

# TODO:
# Current behavior, it will try to add all VMs in the cluster into the backend pool, which would not work since we do not have availability sets created yet.
# In a scale-out scenario, we need to rewrite this code according to the scale-out + HA reference architecture.
resource "azurerm_network_interface_backend_address_pool_association" "hana-lb-nic-bep" {
  count                   = length(azurerm_network_interface.nics-dbnodes-db)
  network_interface_id    = azurerm_network_interface.nics-dbnodes-db[count.index].id
  ip_configuration_name   = azurerm_network_interface.nics-dbnodes-db[count.index].ip_configuration[0].name
  backend_address_pool_id = azurerm_lb_backend_address_pool.hana-lb-back-pool[0].id
}

resource "azurerm_lb_rule" "hana-lb-rules" {
  count                          = length(local.loadbalancers[0].ports)
  resource_group_name            = var.resource-group[0].name
  loadbalancer_id                = azurerm_lb.hana-lb[0].id
  name                           = "HANA_${local.loadbalancers[0].sid}_${local.loadbalancers[0].ports[count.index]}"
  protocol                       = "Tcp"
  frontend_port                  = local.loadbalancers[0].ports[count.index]
  backend_port                   = local.loadbalancers[0].ports[count.index]
  frontend_ip_configuration_name = "hana-${local.loadbalancers[0].sid}-lb-feip"
  backend_address_pool_id        = azurerm_lb_backend_address_pool.hana-lb-back-pool[0].id
  probe_id                       = azurerm_lb_probe.hana-lb-health-probe[0].id
}

# VIRTUAL MACHINES ================================================================================================

# Creates database VM
resource "azurerm_virtual_machine" "vm-dbnode" {
  for_each                      = local.dbnodes
  name                          = each.value.name
  location                      = var.resource-group[0].location
  resource_group_name           = var.resource-group[0].name
  primary_network_interface_id  = azurerm_network_interface.nics-dbnodes-db[each.key].id
  network_interface_ids         = [azurerm_network_interface.nics-dbnodes-admin[each.key].id, azurerm_network_interface.nics-dbnodes-db[each.key].id]
  vm_size                       = lookup(local.sizes, each.value.size).compute.vm_size
  delete_os_disk_on_termination = "true"

  dynamic "storage_os_disk" {
    iterator = disk
    for_each = flatten([for storage_type in lookup(local.sizes, each.value.size).storage : [for disk_count in range(storage_type.count) : { name = storage_type.name, id = disk_count, disk_type = storage_type.disk_type, size_gb = storage_type.size_gb, caching = storage_type.caching }] if storage_type.name == "os"])
    content {
      name              = "${each.value.name}-osdisk"
      caching           = disk.value.caching
      create_option     = "FromImage"
      managed_disk_type = disk.value.disk_type
      disk_size_gb      = disk.value.size_gb
    }
  }

  storage_image_reference {
    publisher = each.value.os.publisher
    offer     = each.value.os.offer
    sku       = each.value.os.sku
    version   = "latest"
  }

  dynamic "storage_data_disk" {
    iterator = disk
    for_each = flatten([for storage_type in lookup(local.sizes, each.value.size).storage : [for disk_count in range(storage_type.count) : { name = storage_type.name, id = disk_count, disk_type = storage_type.disk_type, size_gb = storage_type.size_gb, caching = storage_type.caching, write_accelerator = storage_type.write_accelerator }] if storage_type.name != "os"])
    content {
      name                      = "${each.value.name}-${disk.value.name}-${disk.value.id}"
      caching                   = disk.value.caching
      create_option             = "Empty"
      managed_disk_type         = disk.value.disk_type
      disk_size_gb              = disk.value.size_gb
      write_accelerator_enabled = disk.value.write_accelerator
      lun                       = disk.key
    }
  }

  os_profile {
    computer_name  = each.value.name
    admin_username = each.value.authentication.username
    admin_password = lookup(each.value.authentication, "password", null)
  }

  os_profile_linux_config {
    disable_password_authentication = each.value.authentication.type != "password" ? true : false
    dynamic "ssh_keys" {
      for_each = each.value.authentication.type != "password" ? ["key"] : []
      content {
        path     = "/home/${each.value.authentication.username}/.ssh/authorized_keys"
        key_data = file(var.sshkey.path_to_public_key)
      }
    }
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = var.storage-bootdiag.primary_blob_endpoint
  }
}
