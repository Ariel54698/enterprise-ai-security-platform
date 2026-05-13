output "vpc_name" {
  value = google_compute_network.enterprise_vpc.name

}

output "management_subnet" {
  value = google_compute_subnetwork.management_subnet.name

}

output "application_subnet" {
  value = google_compute_subnetwork.application_subnet.name

}

output "data_subnet" {
  value = google_compute_subnetwork.data_subnet.name

}

