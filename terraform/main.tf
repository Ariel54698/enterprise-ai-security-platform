terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "enterprise_vpc" {
  name                    = "enterprise-security-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "management_subnet" {
  name          = "management-subnet"
  ip_cidr_range = "10.10.1.0/24"
  region        = var.region
  network       = google_compute_network.enterprise_vpc.id
}

resource "google_compute_subnetwork" "application_subnet" {
  name          = "application-subnet"
  ip_cidr_range = "10.10.2.0/24"
  region        = var.region
  network       = google_compute_network.enterprise_vpc.id
}

resource "google_compute_subnetwork" "data_subnet" {
  name          = "date-subnet"
  ip_cidr_range = "10.10.3.0/24"
  region        = var.region
  network       = google_compute_network.enterprise_vpc.id

}

resource "google_compute_firewall" "allow_iap_ssh_to_management" {
  name    = "allow-iap-ssh-to-management"
  network = google_compute_network.enterprise_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["management"]
}

resource "google_compute_firewall" "allow_management_to_internal" {
  name    = "allow-management-to-internal"
  network = google_compute_network.enterprise_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  source_tags = ["management"]
  target_tags = ["application", "data"]
}

resource "google_compute_firewall" "allow_internal_icmp" {
  name    = "allow-internal-icmp"
  network = google_compute_network.enterprise_vpc.name

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.10.0.0/16"]
}

resource "google_compute_router" "enterprise_router" {
  name    = "enterprise-router"
  region  = var.region
  network = google_compute_network.enterprise_vpc.id
}

resource "google_compute_router_nat" "enterprise_nat" {
  name                               = "enterprise-cloud-nat"
  router                             = google_compute_router.enterprise_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_instance" "bastion_host" {
  name         = "bastion-host"
  machine_type = "e2-medium"
  zone         = "me-west1-b"

  tags = ["management"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.management_subnet.id

    access_config {
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  service_account {
    scopes = ["cloud-platform"]
  }
}

resource "google_container_cluster" "enterprise_gke" {
  name     = "enterprise-gke-cluster"
  location = var.zone

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.enterprise_vpc.id
  subnetwork = google_compute_subnetwork.application_subnet.id

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  ip_allocation_policy {
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  deletion_protection = false
}

resource "google_container_node_pool" "secure_node_pool" {
  name       = "secure-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.enterprise_gke.name
  node_count = 2

  node_config {
    machine_type = "e2-medium"

    tags = ["application"]

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

resource "google_artifact_registry_repository" "security_repo" {
  location      = var.region
  repository_id = "security-platform-repo"
  description   = "Enterprise Security Platform Repository"
  format        = "DOCKER"
}