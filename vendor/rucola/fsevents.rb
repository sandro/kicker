begin require 'rubygems'; rescue LoadError; end
require 'fsevent'

module Rucola
  class FSEvents < FSEvent
    class Event
      attr_reader :path

      def initialize(path)
        @path = path
      end

      # Returns an array of the files/dirs in the path that the event occurred in.
      # The files are sorted by the modification time, the first entry is the last modified file.
      def files
        Dir.glob("#{File.expand_path(path)}/*").map do |filename|
          begin
            [File.mtime(filename), filename]
          rescue Errno::ENOENT
            nil
          end
        end.compact.sort.reverse.map { |mtime, filename| filename }
      end

      # Returns the last modified file in the path that the event occurred in.
      def last_modified_file
        files.first
      end
    end

    class StreamError < StandardError; end

    def self.start_watching(*params, &block)
      fsevents = new(*params, &block)
    end

    def initialize(*params, &block)
      raise ArgumentError, 'No callback block was specified.' unless block_given?

      options = params.last.kind_of?(Hash) ? params.pop : {}
      paths = params.flatten

      paths.each { |path| raise ArgumentError, "The specified path (#{path}) does not exist." unless File.exist?(path) }

      watch_directories(paths)
      self.latency = options[:latency] || 0.0
      @user_callback = block
    end

    def on_change(dirs)
      @user_callback.call dirs.map {|p| Event.new(p)}
    end
  end
end
