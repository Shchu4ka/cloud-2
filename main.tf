# Переменные для YC и провайдер
variable "yc_token" {
  default = "t1.9euelZrJlc6UmJ7PnMaPzpKKkIyKx-3rnpWakJLLj8mdxpmUisqelpqZmpfl9PcvWVhI-e84S1P73fT3bwdWSPnvOEtT-83n9euelZqensrPyceaisaRzJWZzI2Pi-_8xeuelZqensrPyceaisaRzJWZzI2Piw.Az234Jo2cGuxH-_iodMGGPeahyfGDj7aJcL-Cp-OONFBsEvsPWyhGvt4YdgWGeuPxWJ3rITxegMVcPfD8-kEAA"
  }
variable "yc_cloud_id" {
  default = "b1g9422l5eafjv34bjtu"
  }
variable "yc_folder_id" {
  default = "b1gosv5aehv25rrbjfq4"
  }
variable "yc_zone" {
  default = "ru-central1-a"
  }

terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone = var.yc_zone
}

# Сервис аккаунт и бакет
resource "yandex_iam_service_account" "sa-bucket" {
  name        = "sa-bucket"
}
resource "yandex_resourcemanager_folder_iam_member" "roleassignment-storageeditor" {
  folder_id = var.yc_folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa-bucket.id}"
}
resource "yandex_iam_service_account_static_access_key" "accesskey-bucket" {
  service_account_id = yandex_iam_service_account.sa-bucket.id
}
resource "yandex_storage_bucket" "kosschuk-170924" {
  access_key = yandex_iam_service_account_static_access_key.accesskey-bucket.access_key
  secret_key = yandex_iam_service_account_static_access_key.accesskey-bucket.secret_key
  bucket     = "kosschuk-170924"
  default_storage_class = "STANDARD"
  acl           = "public-read"
  force_destroy = "true"
  anonymous_access_flags {
    read = true
    list = true
    config_read = true
  }
}

resource "yandex_storage_object" "netology" {
  access_key = yandex_iam_service_account_static_access_key.accesskey-bucket.access_key
  secret_key = yandex_iam_service_account_static_access_key.accesskey-bucket.secret_key
  bucket     = yandex_storage_bucket.kosschuk-170924.id
  key        = "cat.png"
  source     = "cat.png"
}

# VPC
resource "yandex_vpc_network" "network-netology" {
  name = "network-netology"
}

resource "yandex_vpc_subnet" "public" {
  name           = "public"
  zone           = var.yc_zone
  network_id     = yandex_vpc_network.network-netology.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

# Создаем instance-group nlb
resource "yandex_iam_service_account" "sa-group" {
  name        = "sa-group"
}
resource "yandex_resourcemanager_folder_iam_member" "roleassignment-editor" {
  folder_id = var.yc_folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa-group.id}"
}
resource "yandex_compute_instance_group" "group-nlb" {
  name               = "group-nlb"
  folder_id          = var.yc_folder_id
  service_account_id = "${yandex_iam_service_account.sa-group.id}"
  instance_template {
    platform_id = "standard-v1"
    resources {
      memory = 2
      cores  = 2
    }
    boot_disk {
      initialize_params {
        image_id = "fd827b91d99psvq5fjit"
      }
    }
    network_interface {
      network_id = "${yandex_vpc_network.network-netology.id}"
      subnet_ids = ["${yandex_vpc_subnet.public.id}"]
    }
    metadata = {
      ssh-keys  = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
      user-data = "#!/bin/bash\n cd /var/www/html\n echo \"<html><h1>The netology web-server with a network load balancer.</h1><img src='https://${yandex_storage_bucket.kosschuk-170924.bucket_domain_name}/${yandex_storage_object.netology.key}'></html>\" > index.html"
    }
    labels = {
      group = "group-nlb"
    }
  }
  scale_policy {
    fixed_scale {
      size = 3
    }
  }
  allocation_policy {
    zones = [var.yc_zone]
  }
  deploy_policy {
    max_unavailable = 2
    max_expansion   = 1
  }
  load_balancer {
    target_group_name = "target-nlb"
  }
  health_check {
    interval = 15
    timeout = 5
    healthy_threshold = 5
    unhealthy_threshold = 2
    http_options {
      path = "/"
      port = 80
    }
  }
}

# NLB
resource "yandex_lb_network_load_balancer" "nlb" {
  name = "nlb"
  listener {
    name = "nlb-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }
  attached_target_group {
    target_group_id = yandex_compute_instance_group.group-nlb.load_balancer.0.target_group_id
    healthcheck {
      name = "http"
      interval = 10
      timeout = 5
      healthy_threshold = 5
      unhealthy_threshold = 2
      http_options {
        path = "/"
        port = 80
      }
    }
  }
}

# Output
output "ipaddress_group-nlb" {
  value = yandex_compute_instance_group.group-nlb.instances[*].network_interface[0].ip_address
}
output "nlb_address" {
  value = yandex_lb_network_load_balancer.nlb.listener.*.external_address_spec[0].*.address
}
output "picture_url" {
  value = "https://${yandex_storage_bucket.kosschuk-170924.bucket_domain_name}/${yandex_storage_object.netology.key}"
}
