# The keys/signing module generates an ECDSA P-256 private key and holds it in state.
# The image factory signs cached boot assets with it, and nodes verify downloads against
# the matching public key, so the same key has to be returned on every apply — a rotation
# invalidates every asset already signed.

# =============================================================================
# Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "4.1.0"
    }
  }
}

# =============================================================================
# Signing Key
# =============================================================================

resource "tls_private_key" "signing" {
  algorithm   = var.algorithm
  ecdsa_curve = var.ecdsa_curve
}
