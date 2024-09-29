#создает одну ВМ
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"


#---------загрузка файла состояний в s3-------------
  backend "s3" {
    endpoints = {
      s3 = "https://storage.yandexcloud.net"
    }
    bucket = "terraform.st"
    region = "ru-central1"
    key    = "one-server.tfstate"
    shared_credentials_files = [ "di_storage.key" ] #ссылка на ключ доступа к бакету

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true # Необходимая опция Terraform для версии 1.6.1 и старше.
    skip_s3_checksum            = true # Необходимая опция при описании бэкенда для Terraform версии 1.6.3 и старше.

  }
}

provider "yandex" {
  service_account_key_file = "di_key.json"
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = "ru-central1-a"
}

resource "yandex_vpc_network" "infra" {
  name = "EQ-infra"
}

resource "yandex_vpc_subnet" "subnet-infra" {
  v4_cidr_blocks = ["10.2.0.0/16"]
  network_id     = yandex_vpc_network.infra.id
}

#для статического адреса
#resource "yandex_vpc_address" "addr" {
#  name = "staticAddress"
#  external_ipv4_address {
#    zone_id = "ru-central1-a"
#  }
#}

resource "yandex_compute_disk" "boot-disk" {
  name     = "disk-vm1"
  type     = "network-hdd"
  size     = 10
  image_id = "fd87j6d92jlrbjqbl32q"

  labels = {
    environment = "vm-env-labels"
  }
}

#группы безопасности
resource "yandex_vpc_security_group" "group1" {
  name        = "my-security-group"
  description = "description for my security group"
  network_id  = yandex_vpc_network.infra.id

  labels = {
    my-label = "my-label-value"
  }

  dynamic "ingress" {
    for_each = ["22", "80", "443", "3000", "3100", "9090", "9080", "9095", "9100", "9113", "9104" ]
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



resource "yandex_compute_instance" "vm" {
  name        = "instance"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"
  hostname = "instance"

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    disk_id = yandex_compute_disk.boot-disk.id
  }

  network_interface {
    index     = 1
    subnet_id = yandex_vpc_subnet.subnet-infra.id
    nat       = true
    #для статического адреса 
    #nat_ip_address = yandex_vpc_address.addr.external_ipv4_address.0.address
  }

  metadata = {
    #ssh-keys = "fill:${file("~/.ssh/id_ed25519.pub")}"
    user-data = "${file("metafile.yaml")}"
  }
}

#два варианта вывода ip 
#для статического адреса
#output "external_ip" {
#    value = yandex_vpc_address.addr.external_ipv4_address.0.address
#}

resource "yandex_dns_zone" "example_zone" {
  name        = "infrastruct"
  description = "my zone dns"

  labels = {
    label1 = "lable_zone_dns"
  }

  zone    = "infrastruct.ru."
  public  = true
}

resource "yandex_dns_recordset" "vm-test" {
  zone_id = yandex_dns_zone.example_zone.id
  name    = "ldap.infrastruct.ru."
  type    = "A"
  ttl     = 300
  
  data = [yandex_compute_instance.vm.network_interface.0.nat_ip_address]
}

output "instance_ip" {
  value = yandex_compute_instance.vm.network_interface.0.nat_ip_address
}
