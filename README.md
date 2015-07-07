# einheit

Einheit means unit in German.

Einheit is a Nim unit testing library inspired by Python's unit tests. Nim's unittest library is good, but I wanted something a little more "Nim" feeling. I also really like Python's unittest module and thought it would be nice to have something similar in Nim. Also, unittest doesn't have much documentation on how to use it, and it's pretty bare bones, so I wanted a little more functionality and documentation.

The benefit of the macro style I chose means that you can document your tests nicely as well :)

### Description
test_suite is a compile-time macro that allows a user to easily define tests and run them.

Methods are used for inheritance, so if you want to derive a test suite, then you have to make sure the base suite uses methods for the tests that you want to derive.

If you don't want inheritance, you can just use procs.

A special proc/method is called setup(). The macro will inject this method/proc if it doesn't exist and it will be called before running the test suite.

Test methods/procs to be run are prefixed with "test" in the method/proc name. This is so that you can write tests that call procs that do other things and won't be run as a test.

For each suite method/proc, an implicit variable called "self" is added. This lets you access the test_suite in an OO kind of way.

### Installation

Install with nimble!

```bash
nimble install einheit
```

### Usage

```nim
import einheit

test_suite SuiteName of TestSuite:

  var
    suite_var: string
    test_obj: int

  method setup()=
    ## do setup code here
    self.suite_var = "Testing"
    self.test_obj = 90

  method test_adding_string()=
    ## adds a string to the suite_var
    self.suite_var &= " 123"
    self.assert_equal(self.suite_var, "Testing 123")

  proc raises_os()=
    # This proc won't be invoked as a test, it must begin with "test" in lowercase
    raise newException(OSError, "Oh no! OS malfunction!")
  
  method test_raises()=
    # Two ways of asserting
    self.assert_raises OSError:
      self.raises_os()

    self.assert_raises(OSError, self.raises_os())

  method test_test_obj()=
    self.assert_true(self.test_obj == 90)

  method test_more_more()=
    self.assert_false("String" != "String")

  when isMainModule:
    einheit.run_tests()
```

You can also find examples in the [test.nim](test.nim) file, including inheritance . 
