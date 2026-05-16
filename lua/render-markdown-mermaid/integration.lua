local handler = require('render-markdown-mermaid.handler')

local M = {}

---@param config table
---@return render.md.Handler
function M.handler(config)
    return {
        extends = true,
        parse = function(ctx)
            return handler.parse(ctx, config)
        end,
    }
end

return M
