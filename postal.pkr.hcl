locals { 
  my_ami_name = "postal-in-debian-12-${formatdate("YYYY-MM-DD-hhmmss", timestamp())}"
}
packer {
  required_plugins {
    docker = {
      source  = "github.com/hashicorp/docker"
      version = "~> 1"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1"
    }
    git = {
      version = ">= 0.3.5"
      source = "github.com/ethanmdavidson/git"
    }
    vagrant = {
      version = "~> 1"
      source = "github.com/hashicorp/vagrant"
    }
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "docker" "example" {
  #image       = "debian:bookworm"
  image = "debian-with-ansible" #391e836dcff0"
  pull = false
  #export_path = "packer_example"
  commit = true
  #run_command = ["-d", "-i", "-t", "--entrypoint=/bin/bash", "{{.Image}}"]
}

source "vagrant" "example" {
  communicator = "ssh"
  source_path = "debian/bookworm64"
  provider = "virtualbox"
  add_force = true
  #vagrantfile_template = "Vagrant.tmpl"
  template = "Vagrant.tmpl"
}


source "amazon-ebs" "debian-bookworm" {
  ami_name      = local.my_ami_name
  instance_type = "t3.medium"
  region        = "eu-west-3"
  source_ami_filter {
    filters = {
      name                = "*debian-12-amd64-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    # https://wiki.debian.org/Cloud/AmazonEC2Image/Bookworm 
    owners      = ["136693071363"] 
  }
  ssh_username = "admin"
  # FIXME - don't use public IP
  # TODO add user-data with init ssm
  # associate_public_ip_address = false
  # ssh_interface = "private_ip"
  # ssh_interface = "session_manager"

}


build {
  #sources = ["source.docker.example" ]
  #sources = ["source.vagrant.example"]
  sources = ["source.amazon-ebs.debian-bookworm"]

  provisioner "shell" {
      inline = [
        "apt install sudo || echo skip", # docker vs vm
        "sudo apt update",
        "sudo apt -y install ansible"
        ]
  }
  provisioner "ansible-local" {
    playbook_file = "./postal.yml"
    inventory_file = "./hosts"
    # ?? host_alias = "mypostalserver.mydomain.test"
    # ansible-local provisionner
    role_paths = ["roles"] #/home/arthur/tmp/packer/vagrant/output-example/ansible-postal/roles/"]
    group_vars = "group_vars"
    host_vars = "host_vars"
    playbook_dir = "."


    # ansible provisionner
    #inventory_directory = "."
  }

  provisioner "shell" {
    inline = [
      "wget https://s3.eu-west-3.amazonaws.com/amazon-ssm-eu-west-3/latest/debian_amd64/amazon-ssm-agent.deb",
      "sudo dpkg -i amazon-ssm-agent.deb",
      "sudo systemctl enable amazon-ssm-agent"
    ]
  }
  provisioner "shell" {
    inline = [
      "sudo mysqldump --all-databases > /tmp/dump.sql",
      "sudo apt install awscli",
      "echo aws cp /tmp/dump.sql s3://", # TODO 
      "echo sudo apt remove -y --purge mariadb-server" # this goes on RDS
    ]
  }
}

