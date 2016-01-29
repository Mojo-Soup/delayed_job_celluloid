require 'delayed_job_celluloid/command'
require 'delayed_job_celluloid/launcher'
require 'delayed_job_celluloid/manager'
require 'delayed_job_celluloid/worker'

module DelayedJobCelluloid
  class << self
    attr_accessor :logger
  end
end
