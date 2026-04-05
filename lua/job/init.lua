--=============================================================================
-- job.lua ---
-- Copyright (c) 2016-2022 Wang Shidong & Contributors
-- Author: Wang Shidong < wsdjeg@outlook.com >
-- URL: https://spacevim.org
-- License: GPLv3
--=============================================================================

-- Signal constants
local SIGTERM = 15

---@class JobObjState
---@field stdout uv.uv_pipe_t|nil
---@field stderr uv.uv_pipe_t|nil
---@field stdin uv.uv_pipe_t|nil
---@field pid integer
---@field stderr_eof string
---@field stdout_eof string
---@field exited boolean
---@field exit_code integer|nil
---@field exit_signal integer|nil

--- @class JobOpts
--- @field on_stderr? function
--- @field on_exit? fun(id: integer, code: integer, signin: integer)
--- @field on_stdout? function
--- @field cwd? string
--- @field detached? boolean
--- @field clear_env? boolean
--- @field env? table<string, string|number>
--- @field encoding? string
--- @field raw? boolean
--- @field timeout? integer

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
    if std_data[1] == '' and eof ~= '' then
      std_data = { eof }
      eof = ''
    elseif std_data[1] == '' and eof == '' then
      std_data = {}
    elseif std_data[#std_data] ~= '' then
      eof = std_data[#std_data]
      std_data = {}
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

---@param clear_env boolean
---@param env table<string, string|number>
---@return string[] renv
local function setup_env(clear_env, env) -- {{{
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

--- 通用的 stream 处理器设置函数（替代重复的 stdout/stderr 代码）
---@param job_id integer
---@param stream uv.uv_pipe_t
---@param opts JobOpts
---@param stream_name 'stdout'|'stderr'
local function setup_stream_handler(job_id, stream, opts, stream_name)
  local job_key = 'jobid_' .. job_id
  local job = _jobs[job_key]
  if not job then return end

  local state = job.state
  local eof_key = stream_name .. '_eof'
  local callback = stream_name == 'stdout' and opts.on_stdout or opts.on_stderr

  -- 如果没有回调，设置默认处理：收到 EOF 时关闭 stream
  if not callback then
    uv.read_start(stream, function(_, data)
      if not stream or stream:is_closing() or data then
        return
      end
      stream:close()
    end)
    return
  end

  local nparams = debug.getinfo(callback).nparams

  -- 编码转换辅助函数
  local function convert_encoding(data_table)
    if not opts.encoding then return data_table end
    return vim.tbl_map(function(t)
      return vim.fn.iconv(t, opts.encoding, 'utf-8')
    end, data_table)
  end

  -- 调用回调的辅助函数
  local function invoke_callback(data_table)
    vim.schedule(function()
      local converted = convert_encoding(data_table)
      if nparams == 2 then
        callback(job_id, converted)
      else
        callback(job_id, converted, stream_name)
      end
    end)
  end

  -- Raw mode: 直接传递原始数据块
  if opts.raw then
    uv.read_start(stream, function(_, data)
      if data then
        invoke_callback({ data })
      else
        -- EOF
        if stream and not stream:is_closing() then
          stream:close()
        end
      end
    end)
    return
  end

  -- Default: line-buffered mode
  uv.read_start(stream, function(_, data)
    if data then
      local stream_data
      state[eof_key], stream_data = buffered_data(state[eof_key], data)
      if #stream_data > 0 then
        invoke_callback(stream_data)
      end
      return
    end

    -- EOF: 发送剩余缓冲数据
    if state[eof_key] ~= '' then
      invoke_callback({ state[eof_key] })
      state[eof_key] = ''
    end

    if stream and not stream:is_closing() then
      stream:close()
    end
  end)
end

--- Spawns {cmd} as a job.
--- {cmd} can be a string or a table of strings. If {cmd} is a string, it will be
--- executed through the shell. If {cmd} is a table, it will be executed directly.
--- {opts} is a table of job options (see JobOpts).
---
--- Returns an integer, which is the job id if job runs successfully:
--- 	job id: if job started successfully
--- 	0: if type of {cmd} is wrong
--- 	-1: if {cmd}[1] is not executable
--- 	-2: if {opts}.cwd is not a directory
---
--- @param cmd string[]|string
--- @param opts JobOpts
--- @return integer
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
    env = setup_env(opts.clear_env, opts.env),
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
      if job and job.state then
        job.state.exited = true
        job.state.exit_code = code
        job.state.exit_signal = signin
      end

      if job and job.handle and not job.handle:is_closing() then
        job.handle:close()
      end

      -- 清理 job 对象，防止内存泄漏
      _jobs['jobid_' .. current_id] = nil

      vim.schedule(function()
        opts.on_exit(current_id, code, signin)
      end)
    end
  else
    exit_cb = function(code, signin)
      if stdin and not stdin:is_closing() then
        stdin:close()
      end
      local job = _jobs['jobid_' .. current_id]
      if job and job.state then
        job.state.exited = true
        job.state.exit_code = code
        job.state.exit_signal = signin
      end

      if job and job.handle and not job.handle:is_closing() then
        job.handle:close()
      end

      -- 清理 job 对象，防止内存泄漏
      _jobs['jobid_' .. current_id] = nil
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
    exited = false,
    exit_code = nil,
    exit_signal = nil,
  })
  -- logger.debug(vim.inspect(_jobs['jobid_' .. _jobid]))

  -- 使用通用 stream 处理器（替代重复的 stdout/stderr 代码）
  setup_stream_handler(current_id, stdout, opts, 'stdout')
  setup_stream_handler(current_id, stderr, opts, 'stderr')

  if opts.timeout then
    local timer = uv.new_timer()
    if timer then
      timer:start(opts.timeout, 0, function()
        timer:stop()
        timer:close()
        M.stop(current_id, SIGTERM)
      end)
    end
  end

  return current_id
end

--- Sends {data} to stdin of job {id}.
--- {id} is the Job ID returned by Job.start().
--- {data} may be a string or a table of strings. If {data} is nil or empty,
--- stdin will be closed.
---
--- NOTE: If job {id} does not exist or has no stdin stream, an error is raised.
---
--- @param id integer
--- @param data string[]|string|nil
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

--- Closes channel {t} of job {id}.
--- {id} is the Job ID returned by Job.start().
--- {t} can be 'stdin', 'stdout', or 'stderr'.
---
--- NOTE: If job {id} does not exist or {t} is invalid, an error is raised.
---
--- @param id integer
--- @param t 'stdin'|'stdout'|'stderr'
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

--- Stops job {id} by sending {signal}.
--- {id} is the Job ID returned by Job.start().
--- {signal} is the signal number to send (e.g., 9 for SIGKILL).
---
--- NOTE: If job {id} does not exist, this function does nothing.
---
--- @param id integer
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

--- @param id integer
--- @return boolean
function M.is_running(id)
  local job = _jobs['jobid_' .. id]
  return job ~= nil and not job.state.exited
end

--- Waits for Job and it's on_exit handler to complete.
--- {id} is the Job ID of returned by Job.start() function.
--- {timeout} is the maximum waiting time in milliseconds. If
--- omitted or -1, wait forever.
---
--- Returns a integer, which is the status of specific job:
--- 	Exit-code, if the job exited
--- 	-1 if the timeout was exceeded
--- 	-2 if the wait function is cancelled by `<C-c>`
--- 	-3 if the job-id is invalid
---
--- NOTE: press Ctrl-c on Job.wait will not kill the Job.
---
--- @param id integer
--- @param timeout? integer  -- ms, -1 or nil means wait forever
--- @return integer
function M.wait(id, timeout)
  local job = _jobs['jobid_' .. id]
  if not job then
    return -3 -- invalid job-id
  end

  if not timeout or timeout == -1 then
    timeout = 2 ^ 32 - 1
  end

  -- poll only
  if timeout == 0 then
    if job.state.exited and job.state.exit_code then
      return job.state.exit_code
    end
    return -1
  end

  -- • If {callback} returns `true` during the {time}: `true, nil`
  -- • If {callback} never returns `true` during the {time}: `false, -1`
  -- • If {callback} is interrupted during the {time}: `false, -2`
  -- • If {callback} errors, the error is raised.
  local _, reason = vim.wait(timeout, function()
    return job.state.exited
  end)

  if not reason then
    return job.state.exit_code
  end

  -- interrupted (CTRL-C)
  if reason == -2 then
    return -2
  end
  return -1
end

--- @param id integer
--- @return integer|nil
function M.pid(id)
  local job = _jobs['jobid_' .. id]
  if job then
    return job.state.pid
  end
end

return M
-- vim: set ts=4 sts=4 sw=4 et ai si sta:

