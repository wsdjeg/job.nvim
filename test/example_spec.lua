-- test/example_spec.lua
-- Example test file for job.nvim

local lu = require('luaunit')
local job = require('job')

TestJobStart = {}

function TestJobStart:setUp()
  -- Setup if needed
end

function TestJobStart:tearDown()
  -- Cleanup if needed
end

function TestJobStart:test_basic_start()
  local id = job.start({ 'echo', 'hello' }, {
    on_stdout = function(_, data) end,
    on_exit = function(_, code, signal) end,
  })
  lu.assertNotNil(id)
  lu.assertTrue(id > 0)
end

function TestJobStart:test_start_with_string_cmd()
  local id = job.start('echo "hello from shell"', {
    on_stdout = function(_, data) end,
    on_exit = function(_, code, signal) end,
  })
  lu.assertNotNil(id)
  lu.assertTrue(id > 0)
end

function TestJobStart:test_invalid_cmd_type()
  local id = job.start(123, {})
  lu.assertEquals(id, 0)
end

function TestJobStart:test_empty_string_cmd()
  local id = job.start('', {})
  lu.assertEquals(id, 0)
end

function TestJobStart:test_empty_table_cmd()
  local id = job.start({}, {})
  lu.assertEquals(id, 0)
end

function TestJobStart:test_non_executable_cmd()
  local id = job.start({ 'nonexistent_command_xyz' }, {})
  lu.assertEquals(id, -1)
end

function TestJobStart:test_invalid_cwd()
  local id = job.start({ 'echo', 'hello' }, {
    cwd = '/nonexistent/path/xyz',
  })
  lu.assertEquals(id, -2)
end

TestJobSend = {}

function TestJobSend:test_send_and_receive()
  local received = {}
  local id = job.start({ 'cat' }, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        table.insert(received, line)
      end
    end,
    on_exit = function(_, code, signal) end,
  })

  lu.assertTrue(id > 0)

  job.send(id, { 'hello' })
  job.chanclose(id, 'stdin')

  -- Wait for job to complete
  local exit_code = job.wait(id, 5000)
  lu.assertEquals(exit_code, 0)
  lu.assertEquals(received[1], 'hello')
end

TestJobWait = {}

function TestJobWait:test_wait_for_completion()
  local id = job.start({ 'echo', 'test' }, {
    on_stdout = function(_, data) end,
    on_exit = function(_, code, signal) end,
  })

  lu.assertTrue(id > 0)

  local exit_code = job.wait(id, 5000)
  lu.assertEquals(exit_code, 0)
end

function TestJobWait:test_wait_invalid_id()
  local exit_code = job.wait(99999, 1000)
  lu.assertEquals(exit_code, -3)
end

TestJobIsRunning = {}

function TestJobIsRunning:test_running_job()
  local id = job.start({ 'sleep', '1' }, {
    on_exit = function(_, code, signal) end,
  })

  lu.assertTrue(id > 0)
  lu.assertTrue(job.is_running(id))

  -- Wait for it to finish
  job.wait(id, 5000)
  lu.assertFalse(job.is_running(id))
end

function TestJobIsRunning:test_invalid_id()
  lu.assertFalse(job.is_running(99999))
end

TestJobPid = {}

function TestJobPid:test_get_pid()
  local id = job.start({ 'sleep', '1' }, {
    on_exit = function(_, code, signal) end,
  })

  lu.assertTrue(id > 0)

  local pid = job.pid(id)
  lu.assertNotNil(pid)
  lu.assertTrue(pid > 0)

  -- Wait for it to finish
  job.wait(id, 5000)
end

function TestJobPid:test_pid_invalid_id()
  local pid = job.pid(99999)
  lu.assertNil(pid)
end

TestJobStop = {}

function TestJobStop:test_stop_running_job()
  local id = job.start({ 'sleep', '10' }, {
    on_exit = function(_, code, signal) end,
  })

  lu.assertTrue(id > 0)
  lu.assertTrue(job.is_running(id))

  -- Send SIGTERM (15)
  job.stop(id, 15)

  -- Wait for it to finish
  job.wait(id, 5000)
  lu.assertFalse(job.is_running(id))
end

function TestJobStop:test_stop_invalid_id()
  -- Should not error
  job.stop(99999, 15)
end

TestJobChanclose = {}

function TestJobChanclose:test_close_stdin()
  local received = {}
  local id = job.start({ 'cat' }, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        table.insert(received, line)
      end
    end,
    on_exit = function(_, code, signal) end,
  })

  lu.assertTrue(id > 0)

  job.send(id, { 'test data' })
  job.chanclose(id, 'stdin')

  local exit_code = job.wait(id, 5000)
  lu.assertEquals(exit_code, 0)
  lu.assertEquals(received[1], 'test data')
end

function TestJobChanclose:test_invalid_type()
  local id = job.start({ 'echo', 'hello' }, {})

  lu.assertTrue(id > 0)

  -- Should error on invalid type
  lu.assertError(function()
    job.chanclose(id, 'invalid')
  end)

  -- Clean up
  job.wait(id, 5000)
end

return TestJobStart

