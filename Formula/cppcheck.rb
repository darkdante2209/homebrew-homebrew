class Cppcheck < Formula
  desc "Static analysis of C and C++ code"
  homepage "https://sourceforge.net/projects/cppcheck/"
  url "https://github.com/danmar/cppcheck/archive/1.86.tar.gz"
  sha256 "86ea85c2ee5ec31a7410bfc7c206b87e600d284089428750d66d1ce1ffa0c9a6"
  head "https://github.com/danmar/cppcheck.git"

  bottle do
    sha256 "62bc7a5de5fcd3ab3bed91c3e845496553bd4ec1d7dccf043e724e4bfdf36083" => :mojave
    sha256 "f284c2e2b62b1a341c7c0c65d70e1c8e89e260e8a3c6346d0a2f40fe27e381de" => :high_sierra
    sha256 "b67435545ca439c8cba2656ce28f71f8b66c01c2c42f7c6ad650eeeaff0aa655" => :sierra
  end

  depends_on "pcre"

  needs :cxx11

  def install
    ENV.cxx11

    system "make", "HAVE_RULES=yes", "CFGDIR=#{prefix}/cfg"

    # CFGDIR is relative to the prefix for install, don't add #{prefix}.
    system "make", "DESTDIR=#{prefix}", "BIN=#{bin}", "CFGDIR=/cfg", "install"

    # Move the python addons to the cppcheck pkgshare folder
    (pkgshare/"addons").install Dir.glob(bin/"*.py")
  end

  test do
    # Execution test with an input .cpp file
    test_cpp_file = testpath/"test.cpp"
    test_cpp_file.write <<~EOS
      #include <iostream>
      using namespace std;

      int main()
      {
        cout << "Hello World!" << endl;
        return 0;
      }

      class Example
      {
        public:
          int GetNumber() const;
          explicit Example(int initialNumber);
        private:
          int number;
      };

      Example::Example(int initialNumber)
      {
        number = initialNumber;
      }
    EOS
    system "#{bin}/cppcheck", test_cpp_file

    # Test the "out of bounds" check
    test_cpp_file_check = testpath/"testcheck.cpp"
    test_cpp_file_check.write <<~EOS
      int main()
      {
      char a[10];
      a[10] = 0;
      return 0;
      }
    EOS
    output = shell_output("#{bin}/cppcheck #{test_cpp_file_check} 2>&1")
    assert_match "out of bounds", output

    # Test the addon functionality: sampleaddon.py imports the cppcheckdata python
    # module and uses it to parse a cppcheck dump into an OOP structure. We then
    # check the correct number of detected tokens and function names.
    addons_dir = pkgshare/"addons"
    cppcheck_module = "#{name}data"
    expect_token_count = 55
    expect_function_names = "main,GetNumber,Example"
    assert_parse_message = "Error: sampleaddon.py: failed: can't parse the #{name} dump."

    sample_addon_file = testpath/"sampleaddon.py"
    sample_addon_file.write <<~EOS
      #!/usr/bin/env python
      """A simple test addon for #{name}, prints function names and token count"""
      import sys
      import imp
      # Manually import the '#{cppcheck_module}' module
      CFILE, FNAME, CDATA = imp.find_module("#{cppcheck_module}", ["#{addons_dir}"])
      CPPCHECKDATA = imp.load_module("#{cppcheck_module}", CFILE, FNAME, CDATA)

      for arg in sys.argv[1:]:
          # Parse the dump file generated by #{name}
          configKlass = CPPCHECKDATA.parsedump(arg)
          if len(configKlass.configurations) == 0:
              sys.exit("#{assert_parse_message}") # Parse failure
          fConfig = configKlass.configurations[0]
          # Pick and join the function names in a string, separated by ','
          detected_functions = ','.join(fn.name for fn in fConfig.functions)
          detected_token_count = len(fConfig.tokenlist)
          # Print the function names on the first line and the token count on the second
          print "%s\\n%s" %(detected_functions, detected_token_count)
    EOS

    system "#{bin}/cppcheck", "--dump", test_cpp_file
    test_cpp_file_dump = "#{test_cpp_file}.dump"
    assert_predicate testpath/test_cpp_file_dump, :exist?
    output = shell_output("python #{sample_addon_file} #{test_cpp_file_dump}")
    assert_match "#{expect_function_names}\n#{expect_token_count}", output
  end
end