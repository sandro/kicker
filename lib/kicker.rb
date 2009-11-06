$:.unshift File.expand_path('../../vendor', __FILE__)
require 'rucola/fsevents'

require 'kicker/callback_chain'
require 'kicker/core_ext'
require 'kicker/growl'
require 'kicker/options'
require 'kicker/utils'
require 'kicker/validate'

RECIPES_DIR = File.expand_path('../kicker/recipes', __FILE__)
$:.unshift RECIPES_DIR
require 'could_not_handle_file'
require 'execute_cli_command'

USER_RECIPES_DIR = File.expand_path('~/.kick')
$:.unshift USER_RECIPES_DIR if File.exist?(USER_RECIPES_DIR)

class Kicker #:nodoc:
  class << self
    attr_accessor :latency
    
    def latency
      @latency ||= 1
    end
    
    def paths
      @paths ||= %w{ . }
    end
    
    def run(argv = ARGV)
      options = parse_options(argv)
      load_recipes(options[:recipes]) if options[:recipes]
      load_dot_kick
      new(options).start
    end
    
    private
    
    def load_dot_kick
      if File.exist?('.kick')
        require 'dot_kick'
        ReloadDotKick.save_state
        load '.kick'
      end
    end
    
    def load_recipes(recipes)
      recipes.each do |recipe|
        raise "Recipe `#{recipe}' does not exist." unless recipe_exists?(recipe)
        require recipe
      end
    end
    
    def recipe_exists?(recipe)
      File.exist?("#{RECIPES_DIR}/#{recipe}.rb") || File.exist?("#{USER_RECIPES_DIR}/#{recipe}.rb")
    end
  end
  
  attr_reader :latency, :paths, :last_event_processed_at
  
  def initialize(options)
    @paths = (options[:paths] ? options[:paths] : Kicker.paths).map { |path| File.expand_path(path) }
    @latency = options[:latency] || self.class.latency
    
    self.class.use_growl     = options[:growl]
    self.class.growl_command = options[:growl_command]
    
    finished_processing!
  end
  
  def start
    validate_options!
    
    log "Watching for changes on: #{@paths.join(', ')}"
    log ''
    
    run_watch_dog!
    start_growl! if self.class.use_growl
    startup_chain.call([], false)
  end
  
  private
  
  def run_watch_dog!
    dirs = @paths.map { |path| File.directory?(path) ? path : File.dirname(path) }
    watch_dog = Rucola::FSEvents.start_watching(dirs, :latency => @latency) { |events| process(events) }
    trap('INT') do
      log "Exiting…"
      watch_dog.stop
      exit
    end

    watch_dog.start
  end
  
  def finished_processing!
    @last_event_processed_at = Time.now
  end
  
  def process(events)
    unless (files = changed_files(events)).empty?
      full_chain.call(files)
      finished_processing!
    end
  end
  
  def changed_files(events)
    make_paths_relative(events.map do |event|
      files_in_directory(event.path).select { |file| file_changed_since_last_event? file }
    end.flatten.uniq.sort)
  end
  
  def files_in_directory(dir)
    Dir.entries(dir)[2..-1].map { |f| File.join(dir, f) }
  rescue Errno::ENOENT
    []
  end
  
  def file_changed_since_last_event?(file)
    File.mtime(file) > @last_event_processed_at
  rescue Errno::ENOENT
    false
  end
  
  def make_paths_relative(files)
    return files if files.empty?
    wd = Dir.pwd
    files.map do |file|
      if file[0..wd.length-1] == wd
        file[wd.length+1..-1]
      else
        file
      end
    end
  end
end
