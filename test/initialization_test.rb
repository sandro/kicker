require File.expand_path('../test_helper', __FILE__)

describe "Kicker" do
  it "should return the default paths to watch" do
    Kicker.paths.should == %w{ . }
  end
  
  it "should check if a .kick file exists and if so load it before running" do
    Kicker.any_instance.stubs(:start)
    
    File.expects(:exist?).with('.kick').returns(true)
    Kicker.expects(:load).with('.kick')
    Kicker.run
  end
end

describe "Kicker, when initializing" do
  before do
    @now = Time.now
    Time.stubs(:now).returns(@now)
    
    @kicker = Kicker.new(:paths => %w{ /some/dir a/relative/path })
  end
  
  it "should return the extended paths to watch" do
    @kicker.paths.should == ['/some/dir', File.expand_path('a/relative/path')]
  end
  
  it "should have assigned the current time to last_event_processed_at" do
    @kicker.last_event_processed_at.should == @now
  end
  
  it "should use the default paths if no paths were given" do
    Kicker.new({}).paths.should == [File.expand_path('.')]
  end
  
  it "should use the default FSEvents latency if none was given" do
    @kicker.latency.should == 1.5
  end
  
  it "should use the given FSEvents latency if one was given" do
    Kicker.new(:latency => 3.5).latency.should == 3.5
  end
  
  it "should assign whether or not to use growl, and the command, on the Kicker class" do
    Kicker.use_growl = false
    Kicker.growl_command = nil
    Kicker.new(:growl => true, :growl_command => 'ls')
    Kicker.use_growl.should.be true
    Kicker.growl_command.should == 'ls'
  end
end

describe "Kicker, when starting" do
  before do
    @kicker = Kicker.new(:paths => %w{ /some/file.rb })
    @kicker.stubs(:log)
    Rucola::FSEvents.stubs(:start_watching)
    OSX.stubs(:CFRunLoopRun)
  end
  
  it "should show the usage banner and exit when there is no process_callback defined at all" do
    @kicker.stubs(:validate_paths_exist!)
    Kicker.stubs(:process_chain).returns([])
    
    Kicker::OPTION_PARSER_CALLBACK.stubs(:call).returns(mock('OptionParser', :help => 'help'))
    @kicker.expects(:puts).with("help")
    @kicker.expects(:exit)
    
    @kicker.start
  end
  
  it "should warn the user and exit if any of the given paths doesn't exist" do
    @kicker.stubs(:validate_paths_and_command!)
    
    @kicker.expects(:puts).with("The given path `/some/file.rb' does not exist")
    @kicker.expects(:exit).with(1)
    
    @kicker.start
  end
  
  it "should start a FSEvents stream with the assigned latency" do
    @kicker.stubs(:validate_options!)
    
    Rucola::FSEvents.expects(:start_watching).with(['/some'], :latency => @kicker.latency)
    @kicker.start
  end
  
  it "should start a FSEvents stream which watches all paths, but the dirnames of paths if they're files" do
    @kicker.stubs(:validate_options!)
    File.stubs(:directory?).with('/some/file.rb').returns(false)
    
    Rucola::FSEvents.expects(:start_watching).with(['/some'], :latency => @kicker.latency)
    @kicker.start
  end
  
  it "should start a FSEvents stream with a block which calls #process with any generated events" do
    @kicker.stubs(:validate_options!)
    
    Rucola::FSEvents.expects(:start_watching).yields(['event'])
    @kicker.expects(:process).with(['event'])
    
    @kicker.start
  end
  
  it "should setup a signal handler for `INT' which stops the FSEvents stream and exits" do
    @kicker.stubs(:validate_options!)
    
    watch_dog = stub('Rucola::FSEvents')
    Rucola::FSEvents.stubs(:start_watching).returns(watch_dog)
    
    @kicker.expects(:trap).with('INT').yields
    watch_dog.expects(:stop)
    @kicker.expects(:exit)
    
    @kicker.start
  end
  
  it "should start a CFRunLoop" do
    @kicker.stubs(:validate_options!)
    
    OSX.expects(:CFRunLoopRun)
    @kicker.start
  end
  
  it "should register with growl if growl should be used" do
    @kicker.stubs(:validate_options!)
    Kicker.use_growl = true
    
    Growl::Notifier.sharedInstance.expects(:register).with('Kicker', Kicker::GROWL_NOTIFICATIONS.values)
    @kicker.start
  end
  
  it "should _not_ register with growl if growl should not be used" do
    @kicker.stubs(:validate_options!)
    Kicker.use_growl = false
    
    Growl::Notifier.sharedInstance.expects(:register).never
    @kicker.start
  end
end