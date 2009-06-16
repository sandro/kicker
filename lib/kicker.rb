$:.unshift File.expand_path('../../vendor', __FILE__)
require 'rucola/fsevents'
require 'growlnotifier/growl_helpers'
require 'optparse'

class Kicker
  OPTION_PARSER = lambda do |options|
    OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options] -e [command] [paths to watch]"
      
      opts.on('-e', '--execute [COMMAND]', 'The command to execute.') do |command|
        options[:command] = command
      end
      
      opts.on('--[no-]growl', 'Whether or not to use Growl. Default is to use growl.') do |growl|
        options[:growl] = growl
      end
      
      opts.on('--growl-command [COMMAND]', 'The command to execute when the Growl succeeded message is clicked.') do |command|
        options[:growl_command] = command
      end
    end
  end
  
  DEFAULT_FILE_HANDLER = lambda { |file| "sh -c #{file}" }
  
  class << self
    attr_accessor :file_handler, :pre_process, :post_process
    
    def parse_options(argv)
      argv = argv.dup
      options = { :growl => true }
      OPTION_PARSER.call(options).parse!(argv)
      options[:paths] = argv
      options
    end
    
    def log(message)
      puts "[#{Time.now}] #{message}"
    end
    
    def run(argv = ARGV)
      self.file_handler ||= DEFAULT_FILE_HANDLER
      self.pre_process ||= lambda {}
      self.post_process ||= lambda {}
      new( file_handler.nil? ? parse_options( argv ) : { :paths => '.' } ).start
      # new(parse_options(argv)).start
    end
  end
  
  include Growl
  GROWL_NOTIFICATIONS = {
    :change => 'Change occured',
    :succeeded => 'Command succeeded',
    :failed => 'Command failed'
  }
  GROWL_DEFAULT_CALLBACK = lambda do
    OSX::NSWorkspace.sharedWorkspace.launchApplication('Terminal')
  end
  
  attr_writer :command
  attr_reader :paths
  attr_accessor :use_growl, :growl_command
  
  def initialize(options)
    @paths          = options[:paths].map { |path| File.expand_path(path) }
    @command        = options[:command] || "sh -c"
    @use_growl      = options[:growl]
    @growl_command  = options[:growl_command]
    @last_processed = Time.now
  end
  
  def log(message)
    self.class.log(message)
  end
  
  def start
    validate_options!
    
    log "Watching for changes on: #{@paths.join(', ')}"
    log "With command: #{@command}"
    log ''
    
    run_watch_dog!
    start_growl! if @use_growl
    
    OSX.CFRunLoopRun
  end
  
  private
  
  def validate_options!
    validate_paths_and_command!
    validate_paths_exist!
  end
  
  def validate_paths_and_command!
    if @paths.empty? && @command.nil?
      puts OPTION_PARSER.call(nil).help
      exit
    end
  end
  
  def validate_paths_exist!
    @paths.each do |path|
      unless File.exist?(path)
        puts "The given path `#{path}' does not exist"
        exit 1
      end
    end
  end
  
  def log(message)
    puts "[#{Time.now}] #{message}"
  end
  
  def last_command_succeeded?
    $?.success?
  end
  
  def last_command_status
    $?.to_i
  end
  
  def start_growl!
    Growl::Notifier.sharedInstance.register('Kicker', Kicker::GROWL_NOTIFICATIONS.values)
  end
  
  def run_watch_dog!
    dirs = @paths.map { |path| File.directory?(path) ? path : File.dirname(path) }
    watch_dog = Rucola::FSEvents.start_watching(dirs,:latency => 1.5) { |events| process(events) }
    
    trap('INT') do
      log "Cleaning up…"
      watch_dog.stop
      exit
    end
  end
  
  def process( events )
    self.class.pre_process.call
    handle_events( events )
    @last_processed = Time.now
    self.class.post_process.call
  end
  
  def handle_events( events )
    changed_files( events ).each do |file|
      command = self.class.file_handler.call( file )
      execute_command( command ) if command
    end
  end
  
  def changed_files( events )
    events.collect { |event| event.files.select { |file| File.mtime( file ) > @last_processed } }.flatten.collect { |file| file[(Dir.pwd.length + 1)..-1]  }
  end
  
  def execute_command( command )
    log "Change occured. Executing command: #{command}"
    growl(GROWL_NOTIFICATIONS[:change], 'Kicker: Change occured', 'Executing command') if @use_growl
    
    output = `#{command}`
    output.strip.split("\n").each { |line| log "  #{line}" }
    
    log "Command #{last_command_succeeded? ? 'succeeded' : "failed (#{last_command_status})"}"
    
    if @use_growl
      if last_command_succeeded?
        callback = @growl_command.nil? ? GROWL_DEFAULT_CALLBACK : lambda { system(@growl_command) }
        growl(GROWL_NOTIFICATIONS[:succeeded], "Kicker: Command succeeded", output, &callback)
      else
        growl(GROWL_NOTIFICATIONS[:failed], "Kicker: Command failed (#{last_command_status})", output, &GROWL_DEFAULT_CALLBACK)
      end
    end
  end
end

class BatchKicker < Kicker
  DEFAULT_BATCH_HANDLER = lambda { |files| "ruby -e '' -r#{files.join( " -r" )}" }
  
  class << self
    attr_accessor :batch_handler
    
    def run(argv = ARGV)
      self.batch_handler ||= DEFAULT_BATCH_HANDLER
      self.pre_process ||= lambda {}
      self.post_process ||= lambda {}
      new( batch_handler.nil? ? parse_options( argv ) : { :paths => '.' } ).start
    end
    
  end
  
  def handle_events( events )
    command = self.class.batch_handler.call( changed_files( events ) )
    execute_command( command ) if command
  end
  
end
