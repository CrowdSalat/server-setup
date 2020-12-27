terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      version = "1.23.0"
    }
  }
}

variable "hcloud_token" {
    type = string
    sensitive = true
}

provider "hcloud" {
  token = var.hcloud_token
}

data "hcloud_ssh_keys" "all_keys" {
}

data "hcloud_locations" "ds" {
}

output "print_locations" {
  value = data.hcloud_locations.ds
}

output "print_keys" {
  value = data.hcloud_ssh_keys.all_keys
}

resource "hcloud_server" "main" {
  name = "app-server"
  image = "debian-9"
  server_type = "cx11"
  ssh_keys  = [for pub_key in data.hcloud_ssh_keys.all_keys.ssh_keys : pub_key.id]
  location = "nbg1"
}