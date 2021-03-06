require File.expand_path('../../test_helper', __FILE__)

before = Kicker.process_chain.dup
require 'kicker/recipes/jstest'
JSTEST = (Kicker.process_chain - before).first

describe "The HeadlessSquirrel handler" do
  before do
    @files = %w{ Rakefile }
  end
  
  it "should match any test case files" do
    @files += %w{ test/javascripts/ui_test.html test/javascripts/admin_test.js }
    
    Kicker::Utils.expects(:execute).
      with("jstest test/javascripts/ui_test.html test/javascripts/admin_test.html")
    
    JSTEST.call(@files)
    @files.should == %w{ Rakefile }
  end
  
  it "should map public/javascripts libs to test/javascripts" do
    @files += %w{ public/javascripts/ui.js public/javascripts/admin.js }
    
    Kicker::Utils.expects(:execute).
      with("jstest test/javascripts/ui_test.html test/javascripts/admin_test.html")
    
    JSTEST.call(@files)
    @files.should == %w{ Rakefile }
  end
end
