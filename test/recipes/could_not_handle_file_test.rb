require File.expand_path('../../test_helper', __FILE__)

describe "Kicker, concerning the default `could not handle file' callback" do
  it "should log that it could not handle the given files" do
    Kicker.expects(:log).with('')
    Kicker.expects(:log).with("Could not handle: /file/1, /file/2")
    Kicker.expects(:log).with('')
    
    Kicker.post_process_chain.last.call(%w{ /file/1 /file/2 })
  end
end