subscription_id = "eaf4193c-36fa-42b9-b284-5ef3f7e8646c"

isv_hub_connection_name = "conn-isv-demo"
virtual_hub_id          = "/subscriptions/eaf4193c-36fa-42b9-b284-5ef3f7e8646c/resourceGroups/rg-vwan-customer-demo/providers/Microsoft.Network/virtualHubs/vhub-customer-demo"
isv_virtual_network_id  = "/subscriptions/eaf4193c-36fa-42b9-b284-5ef3f7e8646c/resourceGroups/rg-ecs-vwan-isv-core-demo/providers/Microsoft.Network/virtualNetworks/vnet-ecs-vwan-isv-demo"

isv_workload_address_prefix           = "10.100.1.0/24"
nva_load_balancer_frontend_ip_address = "10.100.0.10"
static_route_name                     = "route-isv-workload-via-nva"
associated_route_table_id             = "/subscriptions/eaf4193c-36fa-42b9-b284-5ef3f7e8646c/resourceGroups/rg-vwan-customer-demo/providers/Microsoft.Network/virtualHubs/vhub-customer-demo/hubRouteTables/defaultRouteTable"
propagated_route_table_ids            = ["/subscriptions/eaf4193c-36fa-42b9-b284-5ef3f7e8646c/resourceGroups/rg-vwan-customer-demo/providers/Microsoft.Network/virtualHubs/vhub-customer-demo/hubRouteTables/defaultRouteTable"]
propagated_route_table_labels         = ["default"]
