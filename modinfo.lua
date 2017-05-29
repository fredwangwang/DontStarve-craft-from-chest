name = 'Craft from chest'
description = 'When crafting items, ingredients are automatically obtained from nearby containers. No manually searching for necessary items anymore! '
author = 'fredwangwang'
version = '0.0.1'
forumthread = ''
api_version = 6
priority = 1
dont_starve_compatible = true
reign_of_giants_compatible = false
shipwrecked_compatible = false

icon_atlas = "modicon.xml"
icon = "modicon.tex"

-- dst_compatible = true
-- all_clients_require_mod = false
-- client_only_mod = true
-- server_filter_tags = {}
-- Configurations
configuration_options = {
    {
        name = "range",
        label = "Nearby Range",
        options =
        {
            {description = "10", data = 10},
            {description = "30", data = 30},
            {description = "50", data = 50},
            {description = "100", data = 100},
        },
        default = 30
    },
    {
        name = "is_inv_first",
        label = "Take from: ",
        options =
        {
            {description = "Inv first", data = true},
            {description = "Chest first", data = false},
        },
        default = true
    },
    {
        name = "debug",
        label = "Debug msg",
        options =
        {
            {description = "Enable", data = true},
            {description = "Disable", data = false},
        },
        default = false
    },
}
