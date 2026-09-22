subscription_id = "eaf4193c-36fa-42b9-b284-5ef3f7e8646c"
location        = "Sweden Central"

virtual_hub_address_prefix             = "10.0.0.0/23"
customer_virtual_network_address_space = "10.10.0.0/16"
customer_workload_subnet_prefix        = "10.10.1.0/24"
customer_bastion_subnet_prefix         = "10.10.255.0/26"
isv_workload_address_prefix            = "10.100.1.0/24"

customer_workload_private_ip_address  = "10.10.1.10"
customer_workload_vm_size             = "Standard_B2s"
customer_workload_admin_username      = "azureuser"
customer_workload_ssh_public_key_path = "~/.ssh/fd-fwaas-demo.pub"
customer_workload_zone                = "1"
