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
