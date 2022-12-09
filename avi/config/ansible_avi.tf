resource "null_resource" "ansible_hosts_avi_header_1" {
  provisioner "local-exec" {
    command = "echo '---' | tee hosts_avi; echo 'all:' | tee -a hosts_avi ; echo '  children:' | tee -a hosts_avi; echo '    controller:' | tee -a hosts_avi; echo '      hosts:' | tee -a hosts_avi"
  }
}

resource "null_resource" "ansible_hosts_avi_controllers" {
  depends_on = [null_resource.ansible_hosts_avi_header_1]
  provisioner "local-exec" {
    command = "echo '        ${cidrhost(var.avi.controller.cidr, var.avi.controller.ip)}:' | tee -a hosts_avi "
  }
}

data "template_file" "avi_values" {
  template = file("templates/values_vcenter.yml.template")
  vars = {
    controllerPrivateIp = jsonencode(cidrhost(var.avi.controller.cidr, var.avi.controller.ip))
    ntp = var.vcenter.vds.portgroup.management.external_gw_ip
    dns = var.vcenter.vds.portgroup.management.external_gw_ip
    avi_old_password =  jsonencode(var.avi_old_password)
    avi_password = jsonencode(var.avi_password)
    avi_username = jsonencode(var.avi_username)
    avi_version = var.avi.controller.version
    vsphere_username = "administrator@${var.vcenter.sso.domain_name}"
    vsphere_password = var.vcenter_password
    vsphere_server = "${var.vcenter.name}.${var.external_gw.bind.domain}"
    tenants = jsonencode(var.avi.config.tenants)
    users = jsonencode(var.avi.config.users)
    domain = jsonencode(var.external_gw.bind.domain)
    dc = var.vcenter.datacenter
    ipam = jsonencode(var.avi.config.ipam)
    cloud_name = var.avi.config.cloud.name
    networks = jsonencode(var.avi.config.cloud.networks)
    service_engine_groups = jsonencode(var.avi.config.cloud.service_engine_groups)
    virtual_services = jsonencode(var.avi.config.cloud.virtual_services)
  }
}


resource "null_resource" "ansible_avi" {
  depends_on = [null_resource.ansible_hosts_avi_controllers, vsphere_content_library.nested_library_avi, vsphere_folder.se_groups_folders]

  connection {
    host = var.vcenter.vds.portgroup.management.external_gw_ip
    type = "ssh"
    agent = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "file" {
    source = "hosts_avi"
    destination = "hosts_avi"
  }

  provisioner "file" {
    content = data.template_file.avi_values.rendered
    destination = "values.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "git clone ${var.avi.config.avi_config_repo} --branch ${var.avi.config.avi_config_tag}",
      "cd ${split("/", var.avi.config.avi_config_repo)[4]}",
      "ansible-playbook -i ../hosts_avi vcenter.yml --extra-vars @../values.yml"
    ]
  }
}