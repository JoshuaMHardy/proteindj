variable "REGISTRY" {
  default = "ghcr.io/joshuamhardy"
}

variable "VERSION" {
  default = "v3.0"
}

group "default" {
  targets = ["bindcraft", "fampnn"]
}

group "bindcraft" {
  targets = ["bindcraft-cuda", "bindcraft-rocm"]
}

group "fampnn" {
  targets = ["fampnn-cuda", "fampnn-rocm"]
}

target "bindcraft-cuda" {
  dockerfile = "Dockerfile.bindcraft.dockerfile"
  args = {
    GPU_BACKEND = "cuda"
  }
  tags = ["${REGISTRY}/bindcraft:${VERSION}-cuda"]
  platforms = ["linux/amd64"]
}

target "bindcraft-rocm" {
  dockerfile = "Dockerfile.bindcraft.dockerfile"
  args = {
    GPU_BACKEND = "rocm"
  }
  tags = ["${REGISTRY}/bindcraft:${VERSION}-rocm"]
  platforms = ["linux/amd64"]
}

target "fampnn-cuda" {
  dockerfile = "Dockerfile.fampnn.dockerfile"
  args = {
    GPU_BACKEND = "cuda"
  }
  tags = ["${REGISTRY}/fampnn:${VERSION}-cuda"]
  platforms = ["linux/amd64"]
}

target "fampnn-rocm" {
  dockerfile = "Dockerfile.fampnn.dockerfile"
  args = {
    GPU_BACKEND = "rocm"
  }
  tags = ["${REGISTRY}/fampnn:${VERSION}-rocm"]
  platforms = ["linux/amd64"]
}
