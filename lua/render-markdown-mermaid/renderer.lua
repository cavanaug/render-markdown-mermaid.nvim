local M = {}

---@param value string?
---@return string
local function basename(value)
    if not value or value == '' then
        return ''
    end
    return vim.fs.basename(value)
end

---@param command string[]
---@return string, integer?
local function renderer_kind(command)
    for index, part in ipairs(command) do
        local name = basename(part)
        if name == 'bm' or name == 'mermaid-ascii' then
            return name, index
        end
    end
    return basename(command[1]), nil
end

---@param config table
---@return string[]
local function mermaid_ascii_command(config)
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
---@return string[]
local function bm_command(config)
    local command = vim.deepcopy(config.cmd)
    local _, executable_index = renderer_kind(command)
    local subcommand_index = executable_index and executable_index + 1 or 2
    if command[subcommand_index] ~= 'ascii' then
        table.insert(command, subcommand_index, 'ascii')
    end
    vim.list_extend(command, {
        '--box-padding',
        tostring(config.cli.border_padding),
        '--padding-x',
        tostring(config.cli.padding_x),
        '--padding-y',
        tostring(config.cli.padding_y),
    })
    if config.cli.ascii then
        command[#command + 1] = '--ascii'
    end
    return command
end

---@param config table
---@return string[]
function M.command(config)
    if renderer_kind(config.cmd) == 'bm' then
        return bm_command(config)
    end
    return mermaid_ascii_command(config)
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
                error = vim.trim(result.stderr or ('%s returned no output'):format((select(1, renderer_kind(command))) ~= '' and (select(1, renderer_kind(command))) or 'renderer')),
            })
        end)
    end)
end

return M
