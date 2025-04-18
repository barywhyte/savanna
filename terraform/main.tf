# terraform/main.tf
provider "google" {
  project     = var.project_id
  region      = var.region
  credentials = file("~/Documents/credentials.json")
}

data "google_client_config" "default" {}

resource "google_service_account" "default" {
  account_id   = "service-account-id"
  display_name = "GKE Service Account"
}

resource "google_compute_network" "vpc" {
  name                    = "gke-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "gke-subnet"
  ip_cidr_range            = "10.0.0.0/16"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

resource "google_container_cluster" "primary" {
  name                     = "gke-cluster"
  location                 = var.region
  remove_default_node_pool = true
  initial_node_count       = 1

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "102.89.23.90/32"
      display_name = "my-mac"
    }
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name           = "primary-node-pool"
  location       = var.region
  cluster        = google_container_cluster.primary.name
  node_count     = 1
  node_locations = ["us-central1-a"]

  node_config {
    machine_type    = "e2-medium"
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    service_account = google_service_account.default.email
  }
}

# Kubernetes provider configuration (after cluster creation)
provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

resource "kubernetes_namespace" "staging" {
  depends_on = [google_container_node_pool.primary_nodes]
  
  metadata {
    name = "staging"
  }
}

resource "kubernetes_namespace" "production" {
  depends_on = [google_container_node_pool.primary_nodes]
  
  metadata {
    name = "production"
  }
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "DB-PASSWORD"

  labels = {
    label = "gke"
  }

  replication {
    user_managed {
      replicas {
        location = "us-central1"
      }
      replicas {
        location = "us-east1"
      }
    }
  }
}

resource "google_secret_manager_secret_version" "db_password_ver" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = "supersecretpassword"
}