resource "kubernetes_deployment" "default_http_backend" {
  metadata {
    name = "default-http-backend"
  }
  spec {
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "default-http-backend"
      }
    }
    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "default-http-backend"
        }
      }
      spec {
        container {
          name  = "default-http-backend"
          image = "k8s.gcr.io/defaultbackend-amd64:1.5"
          resources {
            limits = {
              cpu    = "10m"
              memory = "20Mi"
            }
            requests = {
              cpu    = "10m"
              memory = "20Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "default_http_backend" {
  metadata {
    name = "default-http-backend"
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = kubernetes_deployment.default_http_backend.metadata[0].name
    }
    port {
      port        = 80
      target_port = 8080
    }
  }
}

resource "kubernetes_ingress_v1" "default_http_backend" {
  wait_for_load_balancer = true
  metadata {
    name = "default-http-backend"
  }
  spec {
    rule {
      http {
        path {
          backend {
            service {
              name = kubernetes_service.default_http_backend.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
