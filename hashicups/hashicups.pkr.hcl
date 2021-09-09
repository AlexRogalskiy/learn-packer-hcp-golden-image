packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.1-dev"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "ami_prefix" {
  type    = string
  default = "learn-packer-hcp-hashicups"
}

data "packer-image-iteration" "hardened-source" {
  bucket_name = "learn-packer-hcp-golden-base-tonino"
  channel = "production"
}

locals {
  timestamp           = regex_replace(timestamp(), "[- TZ:]", "")
  golden-base-image   = [ for image in flatten(data.packer-image-iteration.hardened-source.builds[*].images[*]): image.image_id ][0]
}

source "amazon-ebs" "hashicups" {
  ami_name      = "${var.ami_prefix}-${local.timestamp}"
  instance_type = "t2.micro"
  region        = "us-east-2"
  #source_ami    = "ami-0461eca8765a82e3e"
  source_ami    = local.golden-base-image
  // source_ami_filter {
  //   filters = {
  //     name                = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
  //     root-device-type    = "ebs"
  //     virtualization-type = "hvm"
  //   }
  //   most_recent = true
  //   owners      = ["099720109477"]
  // }
  ssh_username = "ubuntu"
}

build {
  name = "learn-packer-hashicups"
  sources = [
    "source.amazon-ebs.hashicups"
  ]

  # Add SSH public key
  provisioner "file" {
    source      = "../learn-packer.pub"
    destination = "/tmp/learn-packer.pub"
  }

  # Add HashiCups configuration file
  provisioner "file" {
    source      = "conf.json"
    destination = "conf.json"
  }

  # Add Docker Compose file
  provisioner "file" {
    source      = "docker-compose.yml"
    destination = "docker-compose.yml"
  }

  # Add startup script that will run hashicups on instance boot
  provisioner "file" {
    source      = "start-hashicups.sh"
    destination = "/tmp/start-hashicups.sh"
  }

  # Move temp files to actual destination
  # Must use this method because their destinations are protected 
  provisioner "shell" {
    inline = [
      "sudo cp /tmp/start-hashicups.sh /var/lib/cloud/scripts/per-boot/start-hashicups.sh",
    ]
  }

  # HCP Packer settings
  hcp_packer_registry {
    # Variables not allowed?
    # bucket_name = "learn-packer-hcp-loki-${source.name}"
    bucket_name = "learn-packer-hcp-hashicups-tonino"
    description = <<EOT
This is an image for hashicups built on top of a golden base image.
    EOT

    labels = {
      "foo-version"     = "3.4.0",
      "foo"             = "bar",
      "ubuntu-version"  = "20.04"
    }
  }
}