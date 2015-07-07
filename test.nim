import einheit

test_suite UnitTests:
  var
    test_obj: int

  method setup()=
    self.test_obj = 5
    self.test_obj = 90

  method test_for_b()=
    var b = 0
    self.assert_true(4 == 4)

  method test_for_c()=
    var c = 0
    self.assert_equal(c, 1)


test_suite UnitTestsNew:
  var
    test_obj: int

  method setup()=
    self.test_obj = 5
    self.test_obj = 90

  method test_test_obj()=
    self.assert_true(self.test_obj == 90)

  method test_stuff()=
    self.assert_equal("Stuff", "Stuff")

  method test_more()=
    self.assert_equal("String", "String")

  method test_more_more()=
    self.assert_false("String" != "String")


proc raises_os()=
  raise newException(OSError, "Oh no! OS malfunction!")

# Inheritance!
test_suite TestInherit of UnitTestsNew:
  method test_raises()=

    # Two ways of asserting
    self.assert_raises OSError:
      raises_os()

    self.assert_raises(OSError, raises_os())

when isMainModule:
  run_tests()
