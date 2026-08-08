# specs for the string and terminal helpers in Booker::Output

describe "String extensions" do
  describe "#window" do
    it "should truncate strings longer than width" do
      str = "a" * 100
      result = str.window(10)
      expect(result.length).to eq(10)
    end

    it "should pad strings shorter than width" do
      str = "hello"
      result = str.window(10)
      expect(result.length).to eq(10)
      expect(result).to match(/hello\s+/)
    end

    it "should handle exact width" do
      str = "hello"
      result = str.window(5)
      expect(result).to eq("hello")
    end
  end

  describe "color methods" do
    it "should add color codes" do
      str = "test"
      expect(str.red).to include("\033[")
      expect(str.grn).to include("\033[")
      expect(str.blu).to include("\033[")
      expect(str.yel).to include("\033[")
      expect(str.cyan).to include("\033[")
    end

    it "should reset color codes" do
      str = "test"
      expect(str.reset).to include("\033[0;0m")
    end

    it "should work on empty strings" do
      expect("".red).to be_a(String)
    end
  end
end
