subscription_id = "00000000-0000-0000-0000-000000000000"
location        = "westcentralus"
isv_prefix      = "demo-isv"

virtual_network_address_space  = "192.168.0.0/16"
nva_subnet_address_prefix      = "192.168.0.0/24"
workload_subnet_address_prefix = "192.168.1.0/24"
bastion_subnet_address_prefix  = "192.168.255.0/26"
customer_address_prefix        = "10.10.0.0/16"
isv_forwarding_address_prefix  = "192.168.0.0/16"

nva_frontend_private_ip_address = "192.168.0.10"
nva_vm_size                     = "Standard_B2s_v2"
nva_vm_count                    = 1
nva_zones                       = null
health_probe_port               = 8080
workload_vm_private_ip_address  = "192.168.1.4"
workload_vm_size                = "Standard_B2s_v2"
workload_vm_zone                = null

admin_username      = "azureuser"
ssh_public_key_path = "~/.ssh/fd-fwaas-demo.pub"
