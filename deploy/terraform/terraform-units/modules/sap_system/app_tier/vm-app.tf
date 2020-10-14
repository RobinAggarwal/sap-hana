# Create Application NICs
resource "azurerm_network_interface" "app" {
  count                         = local.enable_deployment ? local.application_server_count : 0
  name                          = format("%s_%s%s", local.prefix, local.app_virtualmachine_names[count.index], local.resource_suffixes.nic)
  location                      = var.resource-group[0].location
  resource_group_name           = var.resource-group[0].name
  enable_accelerated_networking = local.app_sizing.compute.accelerated_networking

  ip_configuration {
    name      = "IPConfig1"
    subnet_id = local.sub_app_exists ? data.azurerm_subnet.subnet-sap-app[0].id : azurerm_subnet.subnet-sap-app[0].id
    private_ip_address = try(local.app_nic_ips[count.index],
      cidrhost(local.sub_web_exists ?
        data.azurerm_subnet.subnet-sap-app[0].address_prefixes[0] :
        azurerm_subnet.subnet-sap-app[0].address_prefixes[0],
        tonumber(count.index) + local.ip_offsets.app_vm
      )
    )
    private_ip_address_allocation = "static"
  }
}

# Create Application NICs
resource "azurerm_network_interface" "app-admin" {
  count                         = local.enable_deployment && local.use_two_network_cards ? local.application_server_count : 0
  name                          = format("%s_%s%s", local.prefix, local.app_virtualmachine_names[count.index], local.resource_suffixes.admin-nic)
  location                      = var.resource-group[0].location
  resource_group_name           = var.resource-group[0].name
  enable_accelerated_networking = local.app_sizing.compute.accelerated_networking

  ip_configuration {
    name      = "IPConfig1"
    subnet_id = local.sub_admin_exists ? data.azurerm_subnet.sap-admin[0].id : azurerm_subnet.sap-admin[0].id
    private_ip_address = try(local.app_admin_nic_ips[count.index],
      cidrhost(local.sub_admin_exists ?
        data.azurerm_subnet.sap-admin[0].address_prefixes[0] :
        azurerm_subnet.sap-admin[0].address_prefixes[0],
        tonumber(count.index) + local.ip_offsets.app_vm
      )
    )
    private_ip_address_allocation = "static"
  }
}

# Create the Linux Application VM(s)
resource "azurerm_linux_virtual_machine" "app" {
  count               = local.enable_deployment ? (upper(local.app_ostype) == "LINUX" ? local.application_server_count : 0) : 0
  name                = format("%s_%s%s", local.prefix, local.app_virtualmachine_names[count.index], local.resource_suffixes.vm)
  computer_name       = local.app_virtualmachine_names[count.index]
  location            = var.resource-group[0].location
  resource_group_name = var.resource-group[0].name

  //If more than one servers are deployed into a zone put them in an availability set and not a zone
  availability_set_id = local.application_server_count == length(local.app_zones) ? null : (
    length(local.app_zones) > 1 ? (
      azurerm_availability_set.app[count.index % length(local.app_zones)].id) : (
      azurerm_availability_set.app[0].id
    )
  )
  proximity_placement_group_id = local.app_zonal_deployment ? var.ppg[count.index % length(local.app_zones)].id : var.ppg[0].id
  zone                         = local.application_server_count == length(local.app_zones) ? local.app_zones[count.index % length(local.app_zones)] : null

  network_interface_ids = local.use_two_network_cards ? (
    [azurerm_network_interface.app[count.index].id, azurerm_network_interface.app-admin[count.index].id]) : (
    [azurerm_network_interface.app[count.index].id]
  )

  size                            = local.app_sizing.compute.vm_size
  admin_username                  = local.authentication.username
  disable_password_authentication = true

  os_disk {
    name                 = format("%s_%s%s", local.prefix, local.app_virtualmachine_names[count.index], local.resource_suffixes.osdisk)
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_id = local.app_custom_image ? local.app_os.source_image_id : null

  dynamic "source_image_reference" {
    for_each = range(local.app_custom_image ? 0 : 1)
    content {
      publisher = local.app_os.publisher
      offer     = local.app_os.offer
      sku       = local.app_os.sku
      version   = local.app_os.version
    }
  }

  admin_ssh_key {
    username   = local.authentication.username
    public_key = file(var.sshkey.path_to_public_key)
  }

  boot_diagnostics {
    storage_account_uri = var.storage-bootdiag.primary_blob_endpoint
  }
}

# Create the Windows Application VM(s)
resource "azurerm_windows_virtual_machine" "app" {
  count               = local.enable_deployment ? (upper(local.app_ostype) == "WINDOWS" ? local.application_server_count : 0) : 0
  name                = format("%s_%s%s", local.prefix, local.app_virtualmachine_names[count.index], local.resource_suffixes.vm)
  computer_name       = local.app_virtualmachine_names[count.index]
  location            = var.resource-group[0].location
  resource_group_name = var.resource-group[0].name

  //If more than one servers are deployed into a zone put them in an availability set and not a zone
  availability_set_id = local.application_server_count == length(local.app_zones) ? null : (
    length(local.app_zones) > 1 ? (
      azurerm_availability_set.app[count.index % length(local.app_zones)].id) : (
      azurerm_availability_set.app[0].id
    )
  )
  proximity_placement_group_id = local.app_zonal_deployment ? var.ppg[count.index % length(local.app_zones)].id : var.ppg[0].id
  zone                         = local.application_server_count == length(local.app_zones) ? (local.app_zones[count.index % length(local.app_zones)]) : null

  network_interface_ids = local.use_two_network_cards ? (
    [azurerm_network_interface.app[count.index].id, azurerm_network_interface.app-admin[count.index].id]) : (
    [azurerm_network_interface.app[count.index].id]
  )

  size           = local.app_sizing.compute.vm_size
  admin_username = local.authentication.username
  admin_password = local.authentication.password

  os_disk {
    name                 = format("%s_%s%s", local.prefix, local.app_virtualmachine_names[count.index], local.resource_suffixes.osdisk)
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_id = local.app_custom_image ? local.app_os.source_image_id : null

  dynamic "source_image_reference" {
    for_each = range(local.app_custom_image ? 0 : 1)
    content {
      publisher = local.app_os.publisher
      offer     = local.app_os.offer
      sku       = local.app_os.sku
      version   = local.app_os.version
    }
  }

  boot_diagnostics {
    storage_account_uri = var.storage-bootdiag.primary_blob_endpoint
  }
}

# Creates managed data disk
resource "azurerm_managed_disk" "app" {
  count                = local.enable_deployment ? length(local.app-data-disks) : 0
  name                 = format("%s_%s%s", local.prefix, local.app_virtualmachine_names[count.index], local.app-data-disks[count.index].suffix)
  location             = var.resource-group[0].location
  resource_group_name  = var.resource-group[0].name
  create_option        = "Empty"
  storage_account_type = local.app-data-disks[count.index].storage_account_type
  disk_size_gb         = local.app-data-disks[count.index].disk_size_gb
  zones = upper(local.app_ostype) == "LINUX" ? (
    [azurerm_linux_virtual_machine.app[local.app-data-disks[count.index].vm_index].zone]) : (
    [azurerm_windows_virtual_machine.app[local.app-data-disks[count.index].vm_index].zone]
  )
}

resource "azurerm_virtual_machine_data_disk_attachment" "app" {
  count                     = local.enable_deployment ? length(azurerm_managed_disk.app) : 0
  managed_disk_id           = azurerm_managed_disk.app[count.index].id
  virtual_machine_id        = upper(local.app_ostype) == "LINUX" ? azurerm_linux_virtual_machine.app[local.app-data-disks[count.index].vm_index].id : azurerm_windows_virtual_machine.app[local.app-data-disks[count.index].vm_index].id
  caching                   = local.app-data-disks[count.index].caching
  write_accelerator_enabled = local.app-data-disks[count.index].write_accelerator_enabled
  lun                       = local.app-data-disks[count.index].lun
}
