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
  default = "learn-packer-hcp-loki-server"
}

# TODO: Externalize this and the one from golden into a parent pkrvars file
# parent.auto.pkrvars.hcl
variable "hcp_packer_suffix" {
  type    = string
  default = "tonino"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "amazon-ebs" "base" {
  ami_name      = "${var.ami_prefix}-${local.timestamp}"
  instance_type = "t2.micro"
  region        = "us-east-2"
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }
  ssh_username = "ubuntu"
}

build {
  name = "learn-packer-loki-server"
  sources = [
    "source.amazon-ebs.base"
  ]

  # Add SSH public key
  provisioner "file" {
    source      = "../learn-packer.pub"
    destination = "/tmp/learn-packer.pub"
  }

  # Add Loki configuration file
  provisioner "file" {
    source      = "loki-local-config.yaml"
    destination = "loki-local-config.yaml"
  }

  # Add startup script that will run loki and grafana on instance boot
  provisioner "file" {
    source      = "start-loki-grafana.sh"
    destination = "/tmp/start-loki-grafana.sh"
  }

  # Execute setup script
  provisioner "shell" {
    script = "loki-setup.sh"
    # Run script after cloud-init finishes, otherwise you run into race conditions
    execute_command = "/usr/bin/cloud-init status --wait && sudo -E -S sh '{{ .Path }}'"
  }

  # Move temp files to actual destination
  # Must use this method because their destinations are protected 
  provisioner "shell" {
    inline = [
      "sudo cp /tmp/start-loki-grafana.sh /var/lib/cloud/scripts/per-boot/start-loki-grafana.sh",
      "rm /tmp/start-loki-grafana.sh",
    ]
  }

  # HCP Packer settings
  hcp_packer_registry {
    # Variables not allowed?
    # bucket_name = "learn-packer-hcp-loki-${source.name}"
    bucket_name = "learn-packer-hcp-loki-tonino"
    description = <<EOT
This is an image for loki built on top of ubuntu 20.04.
    EOT

    labels = {
      "foo-version"     = "3.4.0",
      "foo"             = "bar",
      "ubuntu-version"  = "20.04"
    }
  }
}