local M = {}
M.path_sep = vim.loop.os_uname().sysname == "Windows" and "\\" or "/"

function M.path_join(...) return
    table.concat(vim.tbl_flatten({...}), M.path_sep) end

function M.is_dir(filename)
    local stat = vim.loop.fs_stat(filename)
    return stat and stat.type == 'directory' or false
end

function M.dirname(filepath)
    local is_changed = false
    local result = filepath:gsub(M.path_sep .. "([^" .. M.path_sep .. "]+)$",
                                 function()
        is_changed = true
        return ""
    end)
    return result, is_changed
end

function M.buffer_find_root_dir(bufnr, is_root_path)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if vim.fn.filereadable(bufname) == 0 then return nil end
    local dir = bufname
    -- Just in case our algo is buggy, don't infinite loop.
    for _ = 1, 100 do
        local did_change
        dir, did_change = M.dirname(dir)
        if is_root_path(dir, bufname) then return dir, bufname end
        -- If we can't ascend further, then stop looking.
        if not did_change then return nil end
    end
end

return M
