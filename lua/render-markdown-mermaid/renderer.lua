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
    command = command or {}
    for index, part in ipairs(command) do
        local name = basename(part)
        if name == 'bm' or name == 'mermaid-ascii' then
            return name, index
        end
    end
    return basename(command[1]), nil
end

---@param command string[]
---@param stdout string
---@return string[]
local function output_lines(command, stdout)
    local output = stdout:gsub('\r\n', '\n'):gsub('\n+$', '')
    if output == '' then
        return {}
    end

    local lines = vim.split(output, '\n', { plain = true })
    if renderer_kind(command) == 'bm' and lines[1] and lines[1] ~= '' and not lines[1]:match('^%s') then
        -- Beautiful Mermaid's top border aligns correctly in Neovim with one leading space.
        lines[1] = ' ' .. lines[1]
    end
    return lines
end

---@param config table
---@return boolean
local function is_ascii_mode(config)
    return config.mode == 'ascii'
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
    if is_ascii_mode(config) then
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
    if is_ascii_mode(config) then
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
    local kind = renderer_kind(command)
    vim.system(command, {
        stdin = source,
        text = true,
        timeout = config.timeout,
    }, function(result)
        vim.schedule(function()
            if result.code == 0 and result.stdout and result.stdout ~= '' then
                local lines = output_lines(command, result.stdout)
                if #lines > 0 then
                    callback({ ok = true, output = lines })
                    return
                end
            end

            callback({
                ok = false,
                error = vim.trim(result.stderr or ('%s returned no output'):format(kind ~= '' and kind or 'renderer')),
            })
        end)
    end)
end

return M
