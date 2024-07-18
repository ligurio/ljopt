local dev_checks = function() end

if os.getenv('LJOPT_ENABLE_INTERNAL_CHECKS') then
    dev_checks = require('checks')
end

return dev_checks
