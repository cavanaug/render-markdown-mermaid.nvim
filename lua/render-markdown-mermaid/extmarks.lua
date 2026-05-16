local util = require('render-markdown-mermaid.util')

local M = {}

---@param start_row integer
---@param end_row integer
---@param lines string[]
---@param mode string
---@return render.md.Mark[]
function M.diagram(start_row, end_row, lines, mode)
    if mode == 'disabled' or #lines == 0 then
        return {}
    end

    if mode == 'replace_raw' then
        return {
            {
                conceal = true,
                start_row = start_row,
                start_col = 0,
                opts = {
                    end_row = end_row,
                    end_col = 0,
                    conceal = '',
                    -- Virtual lines render most reliably from a point extmark rather than the
                    -- same range extmark used for concealment.
                    virt_lines = nil,
                    virt_lines_above = false,
                    priority = 200,
                },
            },
            {
                conceal = false,
                start_row = end_row - 1,
                start_col = 0,
                opts = {
                    virt_lines = util.to_virt_lines(lines),
                    virt_lines_above = false,
                    priority = 200,
                },
            },
        }
    end

    return {
        {
            conceal = false,
            start_row = end_row - 1,
            start_col = 0,
            opts = {
                virt_lines = util.to_virt_lines(lines),
                virt_lines_above = false,
                priority = 200,
            },
        },
    }
end

---@param row integer
---@param text string
---@param highlight string
---@return render.md.Mark[]
function M.message(row, text, highlight)
    return {
        {
            conceal = false,
            start_row = row,
            start_col = 0,
            opts = {
                virt_lines = { { { text, highlight } } },
                virt_lines_above = false,
                priority = 200,
            },
        },
    }
end

return M
