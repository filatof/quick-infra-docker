terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
      version = "0.127.0"
    }
  }
  required_version = ">= 0.13"

  backend "s3" {
    endpoints = {
      s3 = "https://storage.yandexcloud.net"
    }
    bucket = "terraform.st"
    region = "ru-central1"
    key    = "final-work.tfstate"
    shared_credentials_files = [ "di_storage.key" ]

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

provider "yandex" {
  service_account_key_file = "di_key.json"
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = "ru-central1-a"
}

resource "yandex_vpc_network" "infra-vpc" {
  name = "infra"
}

resource "yandex_vpc_subnet" "subnet" {
  v4_cidr_blocks = ["10.2.0.0/16"]
  network_id     = yandex_vpc_network.infra-vpc.id
}

resource "yandex_compute_disk" "boot-disk" {
  count    = var.count_num
  name     = "disk-vm${count.index + 1}"
  type     = "network-hdd"
  size     = 20
  image_id = "fd8hglaneh113l00tv83" # ubuntu 22.04 + osLogin 
  labels = {
    environment = "vm-env-labels"
  }
}

resource "yandex_vpc_security_group" "group1" {
  name        = "my-security-group"
  description = "description for my security group"
  network_id  = yandex_vpc_network.infra-vpc.id

  labels = {
    my-label = "my-label-value"
  }

  dynamic "ingress" {
    for_each = ["22", "80", "443", "2376", "2377", "3306", "8080", "3000", "3100", "9090", "9080", "9093", "9095", "9100", "9113", "9104" ]
    content {
      protocol       = "TCP"
      description    = "rule1 description"
      v4_cidr_blocks = ["0.0.0.0/0"]
      from_port      = ingress.value
      to_port        = ingress.value
    }
  }

  egress {
    protocol       = "ANY"
    description    = "rule2 description"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

#-----------Claster-NODE-----------------
resource "yandex_compute_instance" "node" {
  count =var.count_num
  name        = "node-${count.index + 1}"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"
  hostname = "node-${count.index + 1}"

  resources {
    cores         = 2
    memory        = 8
    core_fraction = 20
  }

  boot_disk {
    disk_id = yandex_compute_disk.boot-disk[count.index].id
  }

  network_interface {
    index     = 1
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }

  metadata = {
    #enable-oslogin = true 
    user-data = "${file("metafile.yaml")}"
    #ssh-keys = "my-user:${yandex_organizationmanager_user_ssh_key.my_user_ssh_key.data}"
  }
}


resource "yandex_dns_zone" "example_zone" {
  name        = "infrastruct"
  description = "my zone dns"
  labels = {
    label1 = "lable_zone_dns"
  }
  zone    = "infrastruct.ru."
  public  = true
}

resource "yandex_dns_recordset" "node1" {
  zone_id = yandex_dns_zone.example_zone.id
  name    = "node1.infrastruct.ru."
  type    = "A"
  ttl     = 300
  
  data = [yandex_compute_instance.node[0].network_interface[0].nat_ip_address]
}

resource "yandex_dns_recordset" "node" {
  zone_id = yandex_dns_zone.example_zone.id
  name    = "*.infrastruct.ru."
  type    = "A"
  ttl     = 300
  
  data = [yandex_compute_instance.node[0].network_interface[0].nat_ip_address]
}


output "node_ip" {
  value = [for instance in yandex_compute_instance.node : instance.network_interface[0].nat_ip_address]
}
