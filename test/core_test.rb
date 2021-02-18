# frozen_string_literal: true

require 'minitest/autorun'
require 'logger'
require_relative '../lib/sproc/core'

module SProc
  # test the sequential process class
  class TestSequentialProcess < Minitest::Test
    def test_start_sequential_process
      $stdout.sync = true
      test_str = 'hejsan'
      sp = SProc.new(SProc::NATIVE)
      info = sp.exec_sync('echo', test_str).task_info
      assert_equal("echo #{test_str}", info[:cmd_str])
      assert_equal(true, sp.exit_zero?)
      # the 'echo' cmd adds a newline
      assert_equal(test_str + "\n", info[:stdout])
      assert(info[:stderr].empty?)
    end

    def test_stdout_callback
      $stdout.sync = true
      nof_pings = 2
      matches = 0
      SProc.new(
        SProc::NATIVE,
        ->(line) { (/.*from 127.0.0.1/ =~ line) && (matches += 1) }
      ).exec_sync('ping', ['-c', nof_pings, '127.0.0.1'])

      assert_equal(nof_pings, matches)
    end

    def test_completion_status
      $stdout.sync = true
      # expect this to complete ok (with exit code 0)
      sp = SProc.new(SProc::NATIVE).exec_sync('ping', ['-c', '1', '127.0.0.1'])
      assert_equal(true, sp.exit_zero?)

      # expect this to not have completed when the assert is executed
      sp = SProc.new(SProc::NATIVE).exec_async('ping', ['-c', '1', '127.0.0.1'])
      assert_equal(false, sp.exit_zero?)
      sp.wait_on_completion

      # expect this to complete with exit code != 0 since host does not
      # exist
      sp = SProc.new(SProc::NATIVE).exec_sync('ping', ['-c', '1', 'fake_host'])
      assert_equal(false, sp.exit_zero?)

      # expect this to never start a process since cmd not exists
      sp = SProc.new(SProc::NATIVE).exec_sync('pinggg', ['-c', '1', 'fake_host'])
      assert_equal(false, sp.exit_zero?)
      assert_equal(ExecutionState::FAILED_TO_START, sp.execution_state)
    end

    def test_start_two_parallel_processes
      $stdout.sync = true
      msg_array = %w[hej hopp]
      p_array = msg_array.collect do |str|
        SProc.new(SProc::NATIVE).exec_async('echo', str)
      end
      SProc.wait_on_all(p_array)
      p_array.each_with_index do |p, i|
        info = p.task_info
        assert_equal("echo #{msg_array[i]}", info[:cmd_str])
        assert_equal(true, p.exit_zero?)
        # the 'echo' cmd adds a newline
        assert_equal(msg_array[i] + "\n", info[:stdout])
        assert(info[:stderr].empty?)
      end
    end

    def test_block_yield_wait_all
      # kick-off 4 asynch processes (use ping since it is platform
      # independent)
      p_array = (1..4).collect do
        p = SProc.new(SProc::NATIVE)
        p.exec_async('ping', ['-c','2', '127.0.0.1'])
      end

      nof_finished = 0
      # wait on each process
      SProc.wait_on_all(p_array) do |p|
        nof_finished += 1
        info = p.task_info
        case p.execution_state
        when ExecutionState::ABORTED
          err_str = ["Error: #{info[:stderr]}"]
          err_str << "Process Exception: #{info[:exception]}"
          err_str << 'Did not expect any process to be aborted!!!'
          raise err_str.join("\n")
        end
      end
      assert_equal(4, nof_finished)
      p_array.each do |p|
        assert_equal(p.execution_state, ExecutionState::COMPLETED)
      end
    end

    def test_back_to_back
      # kick-off 4 asynch processes (use ping since it is platform
      # independent)
      p_array = (1..4).collect do
        p = SProc.new(SProc::NATIVE)
        p.exec_async('ping',['-c','2', '127.0.0.1'])
      end

      messages = %w[First Second Third Fourth Fifth]

      nof_finished = 0
      # Wait for the ping processes and kick-off new processes each time one
      # finishes
      p_total = SProc.wait_or_back_to_back(p_array) do |p|
        nof_finished += 1
        raise 'Aouch' if p.execution_state == ExecutionState::ABORTED

        # create new processes as long as there are messages left
        unless messages.empty?
          np = SProc.new.exec_async(
            'echo', messages.shift
          )
        end
        np
      end
      assert_equal(9, nof_finished)
      assert_equal(9, p_total.count)
      p_total.each do |p|
        assert_equal(p.execution_state, ExecutionState::COMPLETED)
      end
    end
  end
end
