$stdout.sync = true

require 'optparse'
require 'celluloid'
require 'daemons'

module DelayedJobCelluloid
  
  class Shutdown < Interrupt; end
  
  class Command
    
    attr_accessor :worker_count

    def logger
      Thread.current[:logger] ||= Logger.new('/tmp/celluloid.log')
      Thread.current[:logger]
    end

    def initialize(args)
      parse_options(args)
    end

    def daemonize

      before_fork
      Daemons.run_proc(@options[:worker_name], :dir => @options[:pid_dir], :dir_mode => :normal, :monitor => @monitor,
                                                                                            :ARGV => @args) do |*_args|
        Celluloid.register_shutdown

        # 'daemons' gem can cwd to '/' which breaks things like New Relic's newrelic.yml loading
        Dir.chdir(Rails.root)
        Celluloid.start

        $0 = File.join(@options[:prefix], 'delayed_job_celluloid') if @options[:prefix]
        launch_celluloid(false)
      end
    end

    def before_fork
      @files_to_reopen = []
        ObjectSpace.each_object(File) do |file|
        @files_to_reopen << file unless file.closed?
      end
    end

    def after_fork
      @files_to_reopen.each do |file|
        begin
          file.reopen file.path, "a+"
          file.sync = true
        rescue ::Exception
        end
      end
    end


    # Run Celluloid in the foreground
    def run

      # Run in the background if daemonizing
      (daemonize; return) if @options[:daemonize]

      # Otherwise, run in the foreground
      launch_celluloid(true)
    end

    def launch_celluloid(in_foreground = true)

      if in_foreground
        Celluloid.start
        self_read, self_write = IO.pipe
        %w(INT TERM).each do |sig|
          trap sig do
            self_write.puts(sig)
          end
        end
      end

      require 'delayed_job_celluloid/launcher'
      @launcher = Launcher.new(@options, @worker_count)

      unless in_foreground
        after_fork

        # Use thread-safe logging
        ::Thread.current[:logger] = Logger.new(@options[:log_file])
        ::Thread.current[:tagged_logger] = ActiveSupport::TaggedLogging.new(Thread.current[:logger])

        # logger.formatter = proc do |severity, datetime, progname, msg|
        #   "#{datetime}: #{msg}\n"
        # end

        logger.info 'Celluloid daemon started'

        # Daemonized - wait to receive a signal
        %w(INT TERM).each do |sig|
          trap sig do
            handle_signal(sig)
          end
        end
      else
        Thread.current[:logger] = Logger.new(@options[:log_file])
      end

      begin

        #logger.info 'Begin celluloid launcher'
        @launcher.run

        if in_foreground
          while readable_io = IO.select([self_read])
            signal = readable_io.first[0].gets.strip
            handle_signal(signal)
          end
        else

          # Sleep for a bit
          while true
            sleep 60
          end

        end
      rescue Interrupt
        logger.info 'Shutting down celluloid launcher'
        @launcher.stop
        exit(0)

      rescue => e
        logger.info "Exception: #{e.message}"
        logger.info Kernel.caller
      end
    end
    
    def handle_signal(signal)
      case signal
      when 'INT','TERM'
        raise Interrupt
      end
    end
    
    def parse_options(args)
      @options = {
        :quiet => true,
        :timeout => 8,
        :log_file => 'celluloid.log',
        :worker_name => 'delayed_job_celluloid'
      }

      @worker_count = 2

      opts = OptionParser.new do |opts|
        opts.banner = "Usage: #{File.basename($0)} [options] start|stop|restart|run"

        opts.on('-h', '--help', 'Show this message') do
          puts opts
          exit 1
        end
        opts.on('-e', '--environment=NAME', 'Specifies the environment to run this delayed jobs under (test/development/production).') do |e|
          STDERR.puts "The -e/--environment option has been deprecated and has no effect. Use RAILS_ENV and see http://github.com/collectiveidea/delayed_job/issues/#issue/7"
        end
        opts.on('--min-priority N', 'Minimum priority of jobs to run.') do |n|
          @options[:min_priority] = n
        end
        opts.on('--max-priority N', 'Maximum priority of jobs to run.') do |n|
          @options[:max_priority] = n
        end
        opts.on('-n', '--number_of_workers=workers', "Number of worker threads to start") do |worker_count|
          @worker_count = worker_count.to_i rescue 1
        end
        opts.on('--pid-dir=DIR', 'Specifies an alternate directory in which to store the process ids.') do |dir|
          @options[:pid_dir] = dir
        end
        opts.on('--worker-name=NAME', 'Specifies an alternate worker name') do |name|
          @options[:worker_name] = name
        end
        opts.on('--worker-prefix=NAME', 'Specifies an alternate internal worker prefix (default is "dj") ') do |name|
          @options[:worker_prefix] = name
        end
        opts.on('--sleep-delay N', "Amount of time to sleep when no jobs are found") do |n|
          @options[:sleep_delay] = n.to_i
        end
        opts.on('--read-ahead N', "Number of jobs from the queue to consider") do |n|
          @options[:read_ahead] = n
        end
        opts.on('-p', '--prefix NAME', "String to be prefixed to worker process names") do |prefix|
          @options[:prefix] = prefix
        end
        opts.on('--queues=queues', "Specify which queue DJ must look up for jobs") do |queues|
          @options[:queues] = queues.split(',')
        end
        opts.on('--priority-queues=queues', 'Specify which queue DJ must look up for URGENT jobs') do |priority_queues|
          @options[:priority_queues] = priority_queues.split(',')
        end
        opts.on('--ignore-priority=sec', 'Specify how long to wait (seconds) before urgent jobs are done by any worker') do |ignore_priority|
          @options[:ignore_priority] = ignore_priority.to_i.seconds
        end
        opts.on('--max-reschedule=count', 'Specify a maximum number of non-urgent jobs to reschedule at a time in a batch') do |count|
          @options[:max_reschedule] = count.to_i
        end
        opts.on('--queue=queue', "Specify which queue DJ must look up for jobs") do |queue|
          @options[:queues] = queue.split(',')
        end
        opts.on('--priority-queue=queue', 'Specify which queue DJ must look up for URGENT jobs') do |priority_queue|
          @options[:priority_queues] = priority_queue.split(',')
        end
        opts.on('--pool=queue1[,queue2][:worker_count]', 'Specify queues and number of workers for a worker pool') do |pool|
          parse_worker_pool(pool)
        end
        opts.on('--exit-on-complete', "Exit when no more jobs are available to run. This will exit if all jobs are scheduled to run in the future.") do
          @options[:exit_on_complete] = true
        end
        opts.on('-t', '--timeout NUM', "Shutdown timeout") do |prefix|
          @options[:timeout] = Integer(arg)
        end
        opts.on('--daemonize', "Daemonize") do
          @options[:daemonize] = true
        end
        opts.on('--log FILE', "Log file for celluloid") do |log_file|
          @options[:log_file] = log_file
        end
      end
      @args = opts.parse!(args)
    end
    
  end
end