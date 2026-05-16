local M = {}

---@param config table
---@return string[]
function M.command(config)
    local command = vim.deepcopy(config.cmd)
    vim.list_extend(command, {
        '-f',
        '-',
        '-p',
        tostring(config.cli.border_padding),
        '-x',
        tostring(config.cli.padding_x),
        '-y',
        tostring(config.cli.padding_y),
    })
    if config.cli.ascii then
        command[#command + 1] = '-a'
    end
    return command
end

---@param config table
---@param source string
---@param callback fun(result: table)
function M.render(config, source, callback)
    local command = M.command(config)
    vim.system(command, {
        stdin = source,
        text = true,
        timeout = config.timeout,
    }, function(result)
        vim.schedule(function()
            if result.code == 0 and result.stdout and result.stdout ~= '' then
                callback({ ok = true, output = vim.split(vim.trim(result.stdout), '\n', { plain = true }) })
                return
            end

            callback({
                ok = false,
                error = vim.trim(result.stderr or 'mermaid-ascii returned no output'),
            })
        end)
    end)
end

return M
