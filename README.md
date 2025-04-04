# job.nvim

job manager for neovim

<!-- vim-markdown-toc GFM -->

* [Installation](#installation)
* [Usage](#usage)
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

```lua
local job = require('job')
local function on_exit(id, code, single)
    print('job exit code:' .. code .. ' single:' .. single)
end

function M.run(argv)
    local cmd = { 'echo', 'hello world' }
    job.start(cmd, { on_exit = on_exit })
end
```

## Self-Promotion

Like this plugin? Star the repository on
GitHub.

Love this plugin? Follow [me](https://wsdjeg.net/) on
[GitHub](https://github.com/wsdjeg) and
[Twitter](http://twitter.com/wsdtty).
