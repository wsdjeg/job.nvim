-- test/util_spec.lua
local lu = require('luaunit')
local job = require('job')

TestJob = {}

function TestJob:testSimpleJob()
  local result = {}
  local jobid = job.start({ 'echo', 'hello world!' }, {
    on_stdout = function(id, data)
      for _, v in ipairs(data) do
        table.insert(result, v)
      end
    end,
  })
  job.wait(jobid, 2000)
  lu.assertStrContains(table.concat(result, '\n'), 'hello')
end

function TestJob:testTimeout()
  local jobid = job.start({ 'sleep', '10' }, {
    timeout = 2000,
    on_exit = function(id, code, signal)
      lu.assertEquals(signal, 15)
    end,
  })
  job.wait(jobid, 10000)
end

return TestJob
