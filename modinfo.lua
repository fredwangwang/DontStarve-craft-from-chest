name = 'Awesome'
description = 'Automatcally use necessary items from nearby containers'
author = 'fredwangwang'
version = '0.0.1'
forumthread = ''
api_version = 6
priority = 1
dont_starve_compatible = true
reign_of_giants_compatible = true
shipwrecked_compatible = false
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
}
