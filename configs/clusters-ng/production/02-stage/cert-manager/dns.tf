resource "google_dns_managed_zone" "default" {
  name        = "default"
  dns_name    = "d20.fan."
}

resource "google_dns_record_set" "default_soa" {
  name = google_dns_managed_zone.default.dns_name
  type = "SOA"
  ttl  = 21600

  managed_zone = google_dns_managed_zone.default.name

  rrdatas = ["ns-cloud-a1.googledomains.com. cloud-dns-hostmaster.google.com. 1 21600 3600 259200 300"]
}

resource "google_dns_record_set" "default_ns" {
  name = google_dns_managed_zone.default.dns_name
  type = "NS"
  ttl  = 21600

  managed_zone = google_dns_managed_zone.default.name

  rrdatas = [
    "ns-cloud-a1.googledomains.com.",
    "ns-cloud-a2.googledomains.com.",
    "ns-cloud-a3.googledomains.com.",
    "ns-cloud-a4.googledomains.com.",
  ]
}
