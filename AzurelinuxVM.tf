terraform {
  required_providers {
    azurerm={
      source="hashicorp/azurerm"
      version = "=2.46.0"
    }
  }
}

provider "azurerm"{
  features {}

}

resource "azurerm_resource_group" "Terraform"{
  name=var.rg
  location = var.location

}


resource "azurerm_network_security_group" "NSGOne" {
  location = var.location
  name = "SSHHTTPfrominternet"
  resource_group_name = azurerm_resource_group.Terraform.name

  security_rule  {
    access = "Allow"
    direction = "Inbound"
    name = "SSHAccess"
    priority = 100
    protocol = "TCP"
    destination_address_prefix = "*"
    destination_port_range = "22"
    source_address_prefix = "0.0.0.0/0"
    source_port_range = "*"
    description = "Rule to accept inbound SSH request"
  }

  security_rule {
    access = "Allow"
    direction = "Inbound"
    name = "HTTPfromInternet"
    priority = 101
    protocol = "TCP"
    destination_port_range = "8080"
    destination_address_prefix = "*"
    source_address_prefix = "0.0.0.0/0"
    source_port_range = "*"
    description = "Inbound Http request"
  }
  tags = {
    environment = "prod"
  }
}

resource "azurerm_network_security_group" "NSGTwo" {
  location = var.location
  name = "SSHfromsubnet1only"
  resource_group_name = azurerm_resource_group.Terraform.name

}


#Creating a Vnet named Vnet1 for Company - Enter resource Group name
resource "azurerm_virtual_network" "vnet1" {
  address_space = ["10.0.0.0/16"]
  location = var.location
  name = "Company"
  resource_group_name = azurerm_resource_group.Terraform.name
  subnet {
    address_prefix = "10.0.1.0/24"
    name = "public"
  }
  subnet {
    address_prefix = "10.0.2.0/24"
    name = "private"
  }
}

resource azurerm_subnet "FrontEnd" {
  name="FrontEnd"
  resource_group_name = azurerm_resource_group.Terraform.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes = ["10.0.3.0/24"]
}

resource azurerm_subnet "BackEnd" {
  name="BackEnd"
  resource_group_name = azurerm_resource_group.Terraform.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes = ["10.0.4.0/24"]
}
resource "azurerm_public_ip" "FrontEndPublicIp" {
  allocation_method = "Dynamic"
  location = var.location
  name = "FrontEndPublicIp"
  resource_group_name = azurerm_resource_group.Terraform.name
}

resource "azurerm_network_interface" "ProductionNic" {
  location = var.location
  name = "ProductionNic"
  resource_group_name = azurerm_resource_group.Terraform.name
  ip_configuration {
    name = "Public"
    subnet_id = azurerm_subnet.FrontEnd.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.FrontEndPublicIp.id
  }
}

resource "azurerm_network_interface" "BackEndNic" {
  location = var.location
  name = "BackEndNic"
  resource_group_name = azurerm_resource_group.Terraform.name
  ip_configuration {
    name = "Private"
    subnet_id = azurerm_subnet.BackEnd.id
    private_ip_address_allocation = "Dynamic"
  }
}
resource "azurerm_network_interface_security_group_association" "linkNSG1toFrontEnd" {
  network_interface_id = azurerm_network_interface.ProductionNic.id
  network_security_group_id = azurerm_network_security_group.NSGOne.id
}

resource "azurerm_network_interface_security_group_association" "linkNSG2toBackEnd" {
  network_interface_id = azurerm_network_interface.BackEndNic.id
  network_security_group_id = azurerm_network_security_group.NSGTwo.id
}

resource "random_id" "randomid" {
  keepers = {
    resource_group = azurerm_resource_group.Terraform.name
  }
  byte_length = 8
}

resource "azurerm_storage_account" "astorageAccount" {
  account_replication_type = "LRS"
  account_tier = "Standard"
  location = var.location
  name = "diag${random_id.randomid.hex}"
  resource_group_name = azurerm_resource_group.Terraform.name
}

resource "tls_private_key" "example_ssh" {
  algorithm = "RSA"
  rsa_bits = 4096

}
output "tls_private_key" {
  value=tls_private_key.example_ssh.private_key_pem
  sensitive = true
}

resource "azurerm_linux_virtual_machine" "ProductionServer" {
  location = var.location
  name = "ProductionServer"
  network_interface_ids = [azurerm_network_interface.ProductionNic.id]
  resource_group_name = azurerm_resource_group.Terraform.name
  admin_username = "adminuser"
  admin_password = "arandompass"
  size = "Standard_B1s"
  computer_name = "ProductionServer"

  os_disk {
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name = "myOSdisk"
  }


  source_image_reference {
    offer = "UbuntuServer"
    publisher = "Canonical"
    sku = "16.04-LTS"
    version = "latest"
  }

  admin_ssh_key {
    public_key = tls_private_key.example_ssh.public_key_openssh
    username = "adminuser"
  }
  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.astorageAccount.primary_blob_endpoint
  }
}
