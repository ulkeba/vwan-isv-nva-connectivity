subscription_id = "00000000-0000-0000-0000-000000000000"
location        = "westcentralus"
customer_prefix = "demo-customer"

virtual_hub_address_prefix             = "10.0.0.0/23"
virtual_hub_deploy_firewall            = true
virtual_hub_route_private_traffic      = true
customer_virtual_network_address_space = "10.10.0.0/16"
customer_workload_subnet_prefix        = "10.10.1.0/24"
customer_bastion_subnet_prefix         = "10.10.255.0/26"
isv_workload_address_prefix            = "192.168.0.0/16"

customer_workload_private_ip_address  = "10.10.1.10"
customer_workload_vm_size             = "Standard_B2s_v2"
customer_workload_admin_username      = "azureuser"
customer_workload_ssh_public_key_path = "~/.ssh/fd-fwaas-demo.pub"
customer_workload_zone                = null
