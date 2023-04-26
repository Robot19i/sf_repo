terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }



backend "s3" {
    endpoint   = "storage.yandexcloud.net"
    bucket     = "tf-state-bucket-makar"
    region     = "ru-central1-a"
    key        = "terraform.tfstate"
    access_key = "KEY"
    secret_key = "SECRET"

    skip_region_validation      = true
    skip_credentials_validation = true
  }
}




# Configure the Yandex.Cloud provider
provider "yandex" {
  token                    = "TOKEN"
  cloud_id                 = "CLOUD"
  folder_id                = "FOLDER"
  zone                     = "ru-central1-a"
}



#Создаем подсети

resource "yandex_vpc_network" "network" {
  name = "network"
}


resource "yandex_vpc_subnet" "subnet1" {
  name           = "subnet1"
  zone = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.88.88.0/24"]
}

resource "yandex_vpc_subnet" "subnet2" {
  name           = "subnet2"
  zone = "ru-central1-b"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.77.77.0/24"]
}

#Модули

module "ya_instance_1" {
  source                = "./modules/instance"
  instance_family_image = "lemp"
  vpc_zone_id    = "ru-central1-a" 
  vpc_subnet_id         = yandex_vpc_subnet.subnet1.id
}

module "ya_instance_2" {
  source                = "./modules/instance"
  instance_family_image = "lamp"
  vpc_zone_id    = "ru-central1-b"
  vpc_subnet_id         = yandex_vpc_subnet.subnet2.id

}


#Руками!

#data "yandex_compute_image" "lamp" {
#  family = "lamp"
#}

#data "yandex_compute_image" "lemp" {
#  family = "lemp"
#}

#resource "yandex_compute_instance" "vm-1" {
#  name                      = "vm-lamp"
#  allow_stopping_for_update = true

#  resources {
#    cores  = 2
#    memory = 2
#  }

#  boot_disk {
#    initialize_params {
#      image_id = data.yandex_compute_image.lamp.id
#    }
#  }

#  network_interface {
#    subnet_id = yandex_vpc_subnet.subnet2.id
#    nat       = true
#  }

#  }

#resource "yandex_compute_instance" "vm-2" {
#  name = "vm-lemp"
#  allow_stopping_for_update = true

#  resources {
#    cores  = 2
#    memory = 2
#  }

#  boot_disk {
#    initialize_params {
#      image_id = data.yandex_compute_image.lemp.id
#    }
#  }

#  network_interface {
#    subnet_id = yandex_vpc_subnet.subnet1.id
#    nat       = true
#  }
#}


#Создаем Балансер


resource "yandex_lb_network_load_balancer" "net-lb" {
  name = "net-lb"

  listener {
    name = "listener-web-servers"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.web.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

resource "yandex_lb_target_group" "web" {
  name = "web-group"

  target {
    subnet_id = yandex_vpc_subnet.subnet1.id
    #address   = yandex_compute_instance.vm.network_interface.0.ip_address
	address = module.ya_instance_1.internal_ip_address_vm  
}

  target {
    subnet_id = yandex_vpc_subnet.subnet2.id
    #address   = yandex_compute_instance.vm.network_interface.0.ip_address
    address = module.ya_instance_2.internal_ip_address_vm  
}
}




# Создаем сервис-аккаунт SA
resource "yandex_iam_service_account" "sa" {
  folder_id = var.folder_id
  name      = "sa-skillfactory"
}

# Даем права на запись для этого SA
resource "yandex_resourcemanager_folder_iam_member" "sa-editor" {
  folder_id = var.folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

# Создаем ключи доступа Static Access Keys
resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.sa.id
  description        = "static access key for object storage"
}

# Создаем хранилище
resource "yandex_storage_bucket" "state" {
  bucket     = "tf-state-bucket-makar"
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
}
