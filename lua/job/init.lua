--=============================================================================
-- job.lua ---
-- Copyright (c) 2016-2022 Wang Shidong & Contributors
-- Author: Wang Shidong < wsdjeg@outlook.com >
-- URL: https://spacevim.org
-- License: GPLv3
--=============================================================================

---@class JobObjState
---@field stdout uv.uv_pipe_t|nil
---@field stderr uv.uv_pipe_t|nil
---@field stdin uv.uv_pipe_t|nil
---@field pid string|integer
---@field stderr_eof string
---@field stdout_eof string

--- @class JobOpts
--- @field on_stderr? function
--- @field on_exit? fun(id: integer, code: integer, signin: integer)
--- @field on_stdout? function
--- @field cwd? string
--- @field detached? boolean
--- @field clear_env? boolean
--- @field env? table<string, string|number>
--- @field encoding? string

---@class JobObj
---@field id integer
---@field handle uv.uv_handle_t
---@field opt JobOpts
---@field state JobObjState

---@class Job
local M = {}

local uv = vim.uv or vim.loop

local _jobs = {} ---@type table<string, JobObj>
local _jobid = 0 ---@type integer

local is_win = vim.fn.has('win32') == 1

---@param eof string
---@param data string
local function buffered_data(eof, data)
    data = data:gsub('\r\n', '\n')
    local std_data = vim.split(data, '\n')
    if #std_data > 1 then
        std_data[1] = eof .. std_data[1]
        eof = std_data[#std_data] == '' and '' or std_data[#std_data]
        table.remove(std_data, #std_data)
    elseif #std_data == 1 then
        std_data = {}
        if std_data[1] == '' and eof ~= '' then
            table.insert(std_data, eof)
            eof = ''
        elseif std_data[#std_data] ~= '' then
            eof = std_data[#std_data]
        end
    end
    return eof, std_data
end

---@param id integer
---@param handle uv.uv_process_t
---@param opt JobOpts
---@param state JobObjState
---@return JobObj obj
local function new_job_obj(id, handle, opt, state)
    return { ---@type JobObj
        id = id,
        handle = handle,
        opt = opt,
        state = state,
    }
end

---@return table<string, string> env
local function default_dev() -- {{{
    local env = vim.fn.environ() ---@type table<string, string>
    env.NVIM = vim.v.servername
    env.NVIM_LISTEN_ADDRESS = nil
    env.NVIM_LOG_FILE = nil
    env.VIMRUNTIME = nil
    return env
end
-- }}}

---@param env table<string, string|number>
---@param clear_env boolean
---@return string[] renv
local function setup_env(env, clear_env) -- {{{
    if clear_env then
        return env
    end

    env = vim.tbl_extend('force', default_dev(), env or {}) ---@type table<string,string|number>

    local renv = {} --- @type string[]
    for k, v in pairs(env) do
        table.insert(renv, ('%s=%s'):format(k, tostring(v)))
    end

    return renv
end
-- }}}

--- @param cmd string[]|string Spawns {cmd} as a job.
--- @param opts JobOpts job options
--- @return 0|-1|-2 job_id # jobid if job run successfully.
---         0: if type of cmd is wrong
---        -1: if cmd[1] is not executable
---        -2: if opts.cwd is not a directory
function M.start(cmd, opts)
    if opts and opts.cwd and vim.fn.isdirectory(opts.cwd) ~= 1 then
        return -2
    end
    if not vim.list_contains({ 'string', 'table' }, type(cmd)) then
        return 0
    end
    opts = opts or {}
    local command = ''
    local argv = {}
    if type(cmd) == 'string' then
        if cmd == '' then
            return 0
        end
        local shell = vim.fn.split(vim.o.shell)
        local shellcmdflag = vim.fn.split(vim.o.shellcmdflag)
        -- :call jobstart(split(&shell) + split(&shellcmdflag) + ['{cmd}'])
        command = shell[1]
        argv = vim.list_slice(shell, 2)
        for _, v in ipairs(shellcmdflag) do
            table.insert(argv, v)
        end
        table.insert(argv, cmd)
    else
        if #cmd == 0 then
            return 0
        end
        for _, v in ipairs(cmd) do
            if type(v) ~= 'string' then
                return 0
            end
        end
        command = cmd[1]
        if command == '' then
            return 0
        end
        if vim.fn.executable(command) == 0 then
            return -1
        end
        argv = vim.list_slice(cmd, 2)
    end
    if is_win then
        local cmd1 = vim.fn.exepath(command)
        if cmd1 ~= '' then
            command = cmd1
        end
    end

    local stdin = uv.new_pipe()
    local stdout = uv.new_pipe()
    local stderr = uv.new_pipe()

    ---@diagnostic disable-next-line:missing-fields
    local opt = { ---@type uv.spawn.options
        stdio = { stdin, stdout, stderr },
        args = argv,
        cwd = opts.cwd or nil,
        hide = true,
        detached = opts.detached or nil,
        env = setup_env(opts.env, opts.clear_env),
    }
    _jobid = _jobid + 1
    local current_id = _jobid
    local exit_cb
    -- https://github.com//neovim/neovim/blob/d9353bd44285a9a3abbe97410730fbf9a252aee3/runtime/lua/vim/_system.lua#L275
    -- #30846: Do not close stdout/stderr here, as they may still have data to
    -- read. They will be closed in uv.read_start on EOF.
    if opts.on_exit then
        ---@param code integer
        ---@param signin integer
        exit_cb = function(code, signin)
            if stdin and not stdin:is_closing() then
                stdin:close()
            end
            local job = _jobs['jobid_' .. current_id]

            if job and job.handle and not job.handle:is_closing() then
                job.handle:close()
            end

            vim.schedule(function()
                opts.on_exit(current_id, code, signin)
            end)
        end
    else
        exit_cb = function()
            if stdin and not stdin:is_closing() then
                stdin:close()
            end
            local job = _jobs['jobid_' .. current_id]

            if job and job.handle and not job.handle:is_closing() then
                job.handle:close()
            end
        end
    end

    local handle, pid = uv.spawn(command, opt, exit_cb)

    -- if handle is nil, we need to close all std channel
    if not handle then
        if stdin and not stdin:is_closing() then
            stdin:close()
        end
        if stdout and not stdout:is_closing() then
            stdout:close()
        end
        if stderr and not stderr:is_closing() then
            stderr:close()
        end
        return -1
    end

    _jobs['jobid_' .. _jobid] = new_job_obj(_jobid, handle, opts, {
        stdout = stdout,
        stderr = stderr,
        stdin = stdin,
        pid = pid,
        stderr_eof = '',
        stdout_eof = '',
    })
    -- logger.debug(vim.inspect(_jobs['jobid_' .. _jobid]))
    if opts.on_stdout then
        -- define on_stdout function based on stdout's nparams
        local nparams = debug.getinfo(opts.on_stdout).nparams
        if nparams == 2 then
            uv.read_start(stdout, function(_, data)
                if data then
                    local stdout_data
                    _jobs['jobid_' .. current_id].state.stdout_eof, stdout_data =
                        buffered_data(_jobs['jobid_' .. current_id].state.stdout_eof, data)
                    if #stdout_data > 0 then
                        vim.schedule(function()
                            if opts.encoding then
                                stdout_data = vim.tbl_map(function(t)
                                    return vim.fn.iconv(t, opts.encoding, 'utf-8')
                                end, stdout_data)
                            end
                            opts.on_stdout(current_id, stdout_data)
                        end)
                    end
                    return
                end

                if _jobs['jobid_' .. current_id].state.stdout_eof ~= '' then
                    local stdout_data = { _jobs['jobid_' .. current_id].state.stdout_eof }
                    _jobs['jobid_' .. current_id].state.stdout_eof = ''
                    vim.schedule(function()
                        if opts.encoding then
                            stdout_data = vim.tbl_map(function(t)
                                return vim.fn.iconv(t, opts.encoding, 'utf-8')
                            end, stdout_data)
                        end
                        opts.on_stdout(current_id, stdout_data)
                    end)
                end
                if stdout and not stdout:is_closing() then
                    stdout:close()
                end
            end)
        else
            uv.read_start(stdout, function(_, data)
                if data then
                    local stdout_data
                    _jobs['jobid_' .. current_id].state.stdout_eof, stdout_data =
                        buffered_data(_jobs['jobid_' .. current_id].state.stdout_eof, data)
                    if #stdout_data > 0 then
                        vim.schedule(function()
                            if opts.encoding then
                                stdout_data = vim.tbl_map(function(t)
                                    return vim.fn.iconv(t, opts.encoding, 'utf-8')
                                end, stdout_data)
                            end
                            opts.on_stdout(current_id, stdout_data, 'stdout')
                        end)
                    end
                    return
                end

                if _jobs['jobid_' .. current_id].state.stdout_eof ~= '' then
                    local stdout_data = { _jobs['jobid_' .. current_id].state.stdout_eof }
                    _jobs['jobid_' .. current_id].state.stdout_eof = ''
                    vim.schedule(function()
                        if opts.encoding then
                            stdout_data = vim.tbl_map(function(t)
                                return vim.fn.iconv(t, opts.encoding, 'utf-8')
                            end, stdout_data)
                        end
                        opts.on_stdout(current_id, stdout_data, 'stdout')
                    end)
                end
                if stdout and not stdout:is_closing() then
                    stdout:close()
                end
            end)
        end
    else
        uv.read_start(stdout, function(_, data)
            if data or not stdout or stdout:is_closing() then
                return
            end

            stdout:close()
        end)
    end

    if opts.on_stderr then
        local nparams = debug.getinfo(opts.on_stderr).nparams
        if nparams == 2 then
            uv.read_start(stderr, function(_, data)
                if data then
                    local stderr_data
                    _jobs['jobid_' .. current_id].state.stderr_eof, stderr_data =
                        buffered_data(_jobs['jobid_' .. current_id].state.stderr_eof, data)
                    if #stderr_data > 0 then
                        vim.schedule(function()
                            if opts.encoding then
                                stderr_data = vim.tbl_map(function(t)
                                    return vim.fn.iconv(t, opts.encoding, 'utf-8')
                                end, stderr_data)
                            end
                            opts.on_stderr(current_id, stderr_data)
                        end)
                    end
                    return
                end

                if _jobs['jobid_' .. current_id].state.stderr_eof ~= '' then
                    local stderr_data = { _jobs['jobid_' .. current_id].state.stderr_eof }
                    _jobs['jobid_' .. current_id].state.stderr_eof = ''
                    vim.schedule(function()
                        if opts.encoding then
                            stderr_data = vim.tbl_map(function(t)
                                return vim.fn.iconv(t, opts.encoding, 'utf-8')
                            end, stderr_data)
                        end
                        opts.on_stderr(current_id, stderr_data)
                    end)
                end
                if stderr and not stderr:is_closing() then
                    stderr:close()
                end
            end)
        else
            uv.read_start(stderr, function(_, data)
                if data then
                    local stderr_data
                    _jobs['jobid_' .. current_id].state.stderr_eof, stderr_data =
                        buffered_data(_jobs['jobid_' .. current_id].state.stderr_eof, data)
                    if #stderr_data > 0 then
                        vim.schedule(function()
                            if opts.encoding then
                                stderr_data = vim.tbl_map(function(t)
                                    return vim.fn.iconv(t, opts.encoding, 'utf-8')
                                end, stderr_data)
                            end
                            opts.on_stderr(current_id, stderr_data, 'stderr')
                        end)
                    end
                    return
                end

                if _jobs['jobid_' .. current_id].state.stderr_eof ~= '' then
                    local stderr_data = { _jobs['jobid_' .. current_id].state.stderr_eof }
                    _jobs['jobid_' .. current_id].state.stderr_eof = ''
                    vim.schedule(function()
                        if opts.encoding then
                            stderr_data = vim.tbl_map(function(t)
                                return vim.fn.iconv(t, opts.encoding, 'utf-8')
                            end, stderr_data)
                        end
                        opts.on_stderr(current_id, stderr_data, 'stderr')
                    end)
                end
                if stderr and not stderr:is_closing() then
                    stderr:close()
                end
            end)
        end
    else
        uv.read_start(stderr, function(_, data)
            if data or not stderr or stderr:is_closing() then
                return
            end

            stderr:close()
        end)
    end
    return current_id
end

--- @param id integer job id
--- @param data string[]|string|nil  {data} may be a string or a table of string.
function M.send(id, data) -- {{{
    if not _jobs['jobid_' .. id] then
        error('Unable to find job: ' .. id)
    end

    local stdin = _jobs['jobid_' .. id].state.stdin
    if not stdin then
        error('no stdin stream for jobid:' .. id)
    end

    if not (data and vim.list_contains({ 'table', 'string' }, type(data))) then
        stdin:write('', function()
            stdin:shutdown(function()
                stdin:close()
            end)
        end)
        return
    end
    if type(data) == 'table' then
        for _, v in ipairs(data) do
            stdin:write(v)
            stdin:write('\n')
        end
        return
    end

    stdin:write(data)
    stdin:write('\n')
end

--- @param id integer job id
--- @param t 'stdin'|'stdout'|'stderr' std type, stdin, stdout or stderr
function M.chanclose(id, t)
    if not _jobs['jobid_' .. id] then
        error('Unable to find job: ' .. id)
    end
    if not vim.list_contains({ 'stdout', 'stderr', 'stdin' }, t) then
        error('type can only be: stdout, stdin or stderr')
    end

    local stream = _jobs['jobid_' .. id].state[t] ---@type uv.uv_pipe_t|nil
    if stream and not stream:is_closing() then
        stream:close()
    end
end

--- @param id integer stop job with specific {id}
--- @param signal integer
function M.stop(id, signal)
    if not (id and _jobs['jobid_' .. id]) then
        return
    end

    local handle = _jobs['jobid_' .. id].handle
    if handle then
        handle:kill(signal)
    end
end
return M
-- vim: set ts=4 sts=4 sw=4 et ai si sta:
