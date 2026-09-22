subscription_id = "eaf4193c-36fa-42b9-b284-5ef3f7e8646c"
location        = "swedencentral"

virtual_network_address_space  = "10.100.0.0/16"
nva_subnet_address_prefix      = "10.100.0.0/24"
workload_subnet_address_prefix = "10.100.1.0/24"
bastion_subnet_address_prefix  = "10.100.255.0/26"
customer_address_prefix        = "10.10.0.0/16"

nva_frontend_private_ip_address = "10.100.0.10"
nva_vm_size                     = "Standard_B2s"
nva_zones                       = ["1", "2"]
health_probe_port               = 8080
workload_vm_private_ip_address  = "10.100.1.4"
workload_vm_size                = "Standard_B2s"
workload_vm_zone                = "1"

admin_username      = "azureuser"
ssh_public_key_path = "~/.ssh/fd-fwaas-demo.pub"
