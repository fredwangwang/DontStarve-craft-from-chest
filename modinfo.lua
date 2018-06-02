name = 'Craft from chest DST'
description = 'When crafting items, ingredients are automatically obtained from nearby containers. No manually searching for necessary items anymore! '
author = 'fredwangwang'
version = '1.1.0'
forumthread = ''
api_version = 6
api_version_dst = 10 
priority = 1
dont_starve_compatible = true
reign_of_giants_compatible = true
shipwrecked_compatible = true
dst_compatible = true
all_clients_require_mod = false
client_only_mod = true
server_filter_tags = {}

icon_atlas = "modicon.xml"
icon = "modicon.tex"

configuration_options = {
    {
		name = "enable",
		label = "Enable?",
		hover = "Choose to enable the mod or not",
		options =	{
						{description = "Disabled", data = false},
                        {description = "Enabled", data = true},
					},
		default = true,
	},
    {
        name = "range",
        label = "Nearby Range",
        options =
        {
            {description = "10", data = 10},
            {description = "30", data = 30},
            {description = "50", data = 50},
        },
        default = 10
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
