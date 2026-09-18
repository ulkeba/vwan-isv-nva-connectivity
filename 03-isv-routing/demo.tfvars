subscription_id = "eaf4193c-36fa-42b9-b284-5ef3f7e8646c"
location        = "swedencentral"

resource_group_name = "rg-ecs-vwan-isv-core-demo"
route_table_name    = "rt-ecs-vwan-isv-to-customer-demo"
route_name          = "customer-vnet-via-nva"

isv_workload_subnet_id          = "/subscriptions/eaf4193c-36fa-42b9-b284-5ef3f7e8646c/resourceGroups/rg-ecs-vwan-isv-core-demo/providers/Microsoft.Network/virtualNetworks/vnet-ecs-vwan-isv-demo/subnets/snet-workload"
customer_address_prefix         = "10.10.0.0/16"
nva_frontend_private_ip_address = "10.100.0.10"
