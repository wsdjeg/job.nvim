# job.nvim

job manager for neovim

<!-- vim-markdown-toc GFM -->

* [Installation](#installation)
* [Usage](#usage)
* [APIs](#apis)
* [Self-Promotion](#self-promotion)

<!-- vim-markdown-toc -->

## Installation

using [nvim-plug](https://github.com/wsdjeg/nvim-plug)

```lua
require("plug").add({
	{
		"wsdjeg/job.nvim",
	},
})
```

## Usage

example:

```lua
local job = require('job')
local function on_exit(id, code, single)
    print('job ' .. id .. ' exit code:' .. code .. ' single:' .. single)
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
    on_exit = function(id, code, single)
        print('job ' .. id .. ' exit code:' .. code .. ' single:' .. single)
    end,
})

job.send(jobid, { 'hello' })

job.chanclose(jobid, 'stdin')
```

output:

```
jobid is 43
{ "hello world" }
job 43 exit code:0 single:0
{ "hello" }
job 44 exit code:0 single:0
```

## APIs

| function                    | description               |
| --------------------------- | ------------------------- |
| `job.start(cmd, opt)`       | start a new job           |
| `job.stop(jobid, signal)`   | stop the job with signal  |
| `job.send(jobid, data)`     | send data to specific job |
| `job.chanclose(jobid, std)` | close channel of a job    |

## Self-Promotion

Like this plugin? Star the repository on
GitHub.

Love this plugin? Follow [me](https://wsdjeg.net/) on
[GitHub](https://github.com/wsdjeg) and
[Twitter](http://twitter.com/wsdtty).
