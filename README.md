# job.nvim

job manager for neovim

[![GitHub License](https://img.shields.io/github/license/wsdjeg/job.nvim)](LICENSE)
[![GitHub Issues or Pull Requests](https://img.shields.io/github/issues/wsdjeg/job.nvim)](https://github.com/wsdjeg/job.nvim/issues)
[![GitHub commit activity](https://img.shields.io/github/commit-activity/m/wsdjeg/job.nvim)](https://github.com/wsdjeg/job.nvim/commits/master/)
[![GitHub Release](https://img.shields.io/github/v/release/wsdjeg/job.nvim)](https://github.com/wsdjeg/job.nvim/releases)
[![luarocks](https://img.shields.io/luarocks/v/wsdjeg/job.nvim)](https://luarocks.org/modules/wsdjeg/job.nvim)

<!-- vim-markdown-toc GFM -->

- [Installation](#installation)
- [Usage](#usage)
    - [Using a shell command string](#using-a-shell-command-string)
    - [Error handling](#error-handling)
- [APIs](#apis)
    - [`job.start(cmd, opts)`](#jobstartcmd-opts)
    - [`job.stop(id, signal)`](#jobstopid-signal)
    - [`job.send(id, data)`](#jobsendid-data)
    - [`job.chanclose(id, t)`](#jobchancloseid-t)
    - [`job.is_running(id)`](#jobis_runningid)
    - [`job.wait(id, timeout)`](#jobwaitid-timeout)
- [Job options](#job-options)
    - [encoding](#encoding)
    - [cwd](#cwd)
    - [detached](#detached)
    - [clear_env](#clear_env)
    - [env](#env)
- [Error codes](#error-codes)
- [Callback signatures](#callback-signatures)
    - [`on_stdout(id, data[, stream])`](#on_stdoutid-data-stream)
    - [`on_stderr(id, data[, stream])`](#on_stderrid-data-stream)
    - [`on_exit(id, code, signal)`](#on_exitid-code-signal)
- [Self-Promotion](#self-promotion)

<!-- vim-markdown-toc -->

## Installation

Using [nvim-plug](https://github.com/wsdjeg/nvim-plug)

```lua
require("plug").add({
	{
		"wsdjeg/job.nvim",
	},
})
```

Using [luarocks](https://luarocks.org/)

```
luarocks install job.nvim
```

Alternatively, using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
	"wsdjeg/job.nvim",
	config = function()
		-- No configuration needed
	end,
}
```

## Usage

Basic example:

```lua
local job = require('job')
local function on_exit(id, code, signal)
    print('job ' .. id .. ' exit code:' .. code .. ' signal:' .. signal)
end

local cmd = { 'echo', 'hello world' }
local jobid1 = job.start(cmd, {
    on_stdout = function(id, data)
        vim.print(data)
    end,
    on_exit = on_exit,
})

vim.print(string.format('jobid is %s', jobid1))

local jobid = job.start({ 'cat' }, {
    on_stdout = function(id, data)
        vim.print(data)
    end,
    on_exit = function(id, code, signal)
        print('job ' .. id .. ' exit code:' .. code .. ' signal:' .. signal)
    end,
})

job.send(jobid, { 'hello' })

job.chanclose(jobid, 'stdin')
```

Output:

```
jobid is 43
{ "hello world" }
job 43 exit code:0 signal:0
{ "hello" }
job 44 exit code:0 signal:0
```

### Using a shell command string

```lua
local jobid = job.start('echo "hello from shell"', {
    on_stdout = function(id, data) vim.print(data) end,
})
```

### Error handling

`job.start` returns a positive integer job ID on success, or one of the following error codes:

- `0`: invalid command type or empty command
- `-1`: command not executable or spawn failure
- `-2`: `cwd` option is not a directory

Example:

```lua
local id = job.start({ '' }, {})
if id <= 0 then
    vim.print('Failed to start job, error code:', id)
end
```

## APIs

| function                    | description                                    | returns                        |
| --------------------------- | ---------------------------------------------- | ------------------------------ |
| `job.start(cmd, opt)`       | start a new job                                | job id (>0) or error code (≤0) |
| `job.stop(jobid, signal)`   | stop the job with signal (integer)             | none                           |
| `job.send(jobid, data)`     | send data (string or table of strings) to job  | none                           |
| `job.chanclose(jobid, std)` | close channel (`stdin`, `stdout`, or `stderr`) | none                           |

### `job.start(cmd, opts)`

- `cmd` (string|table): command to execute. If a string, it is passed to the shell. If a table, the first element is the executable and the rest are arguments.
- `opts` (table|nil): job options (see [Job options](#job-options)).

### `job.stop(id, signal)`

- `id` (integer): job ID returned by `job.start`.
- `signal` (integer): POSIX signal number (e.g., 9 for SIGKILL, 15 for SIGTERM).

### `job.send(id, data)`

- `id` (integer): job ID.
- `data` (string|table|nil): data to send. If a table, each element is written as a line. If nil, an empty string is sent and stdin is shut down.

### `job.chanclose(id, t)`

- `id` (integer): job ID.
- `t` (string): which channel to close: `"stdin"`, `"stdout"`, or `"stderr"`.

### `job.is_running(id)`

- `id` (integer): job ID.

### `job.wait(id, timeout)`

- `id` (integer): job ID.
- `timeout` (integer): maximum waiting time in milliseconds.

## Job options

All options are optional.

### encoding

If the output encoding of a job command is not UTF‑8, set this option to convert the output automatically.

Example:

```lua
job.start({ 'iconv', '-f', 'gbk', 'file.txt' }, {
    encoding = 'gbk',
    on_stdout = function(id, data) vim.print(data) end,
})
```

### cwd

Working directory for the job.

```lua
job.start({ 'pwd' }, { cwd = '/tmp' })
```

### detached

If `true`, the job will run in a detached state (see `uv.spawn` documentation).

### clear_env

If `true`, only the environment variables provided in `env` will be passed to the job. By default the job inherits the current environment (with some Neovim‑specific variables removed).

### env

Table of environment variables to set for the job. Values can be strings or numbers.

```lua
job.start({ 'printenv', 'MY_VAR' }, {
    env = { MY_VAR = 'hello' },
    on_stdout = function(id, data) vim.print(data) end,
})
```

## Error codes

| code | meaning                                                            |
| ---- | ------------------------------------------------------------------ |
| 0    | invalid command type, empty command string, or empty command table |
| -1   | command is not executable, or `uv.spawn` failed                    |
| -2   | `opts.cwd` exists but is not a directory                           |

## Callback signatures

### `on_stdout(id, data[, stream])`

Called when the job writes to stdout.

- `id` (integer): job ID.
- `data` (table): list of output lines (strings).
- `stream` (string, optional): if the callback accepts three parameters, this will be `"stdout"`.

### `on_stderr(id, data[, stream])`

Called when the job writes to stderr. Same signature as `on_stdout`.

### `on_exit(id, code, signal)`

Called when the job exits.

- `id` (integer): job ID.
- `code` (integer): exit code.
- `signal` (integer): signal number (0 if the job exited normally).

## Self-Promotion

Like this plugin? Star the repository on
GitHub.

Love this plugin? Follow [me](https://wsdjeg.net/) on
[GitHub](https://github.com/wsdjeg).
