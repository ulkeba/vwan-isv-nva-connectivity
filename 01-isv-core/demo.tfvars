subscription_id = "eaf4193c-36fa-42b9-b284-5ef3f7e8646c"
location        = "swedencentral"

resource_group_name  = "rg-ecs-vwan-isv-core-demo"
virtual_network_name = "vnet-ecs-vwan-isv-demo"

virtual_network_address_space  = "10.100.0.0/16"
nva_subnet_name                = "snet-nva"
nva_subnet_address_prefix      = "10.100.0.0/24"
workload_subnet_name           = "snet-workload"
workload_subnet_address_prefix = "10.100.1.0/24"
bastion_subnet_address_prefix  = "10.100.255.0/26"
customer_address_prefix        = "10.10.0.0/16"

nva_name_prefix                      = "ecs-vwan-isv-nva"
nva_network_security_group_name      = "nsg-ecs-vwan-isv-nva-demo"
nva_frontend_private_ip_address      = "10.100.0.10"
nva_vm_size                          = "Standard_B2s"
nva_zones                            = ["1", "2"]
health_probe_port                    = 8080
workload_vm_name                     = "vm-ecs-vwan-isv-workload-demo"
workload_network_security_group_name = "nsg-ecs-vwan-isv-workload-demo"
workload_vm_private_ip_address       = "10.100.1.4"
workload_vm_size                     = "Standard_B2s"
workload_vm_zone                     = "1"

admin_username      = "azureuser"
ssh_public_key_path = "~/.ssh/ecs-vwan-fwaas-demo.pub"

bastion_name           = "bas-ecs-vwan-isv-demo"
bastion_public_ip_name = "pip-ecs-vwan-isv-bastion-demo"
