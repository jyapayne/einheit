import einheit

test_suite UnitTests:
  var
    test_obj: int

  proc do_things()=
    # This proc won't be invoked as a test
    self.test_obj = 400
    self.assert_true(self.test_obj == 400)

  method setup()=
    self.test_obj = 5
    self.test_obj = 90

  method test_for_b()=
    var b = 0
    self.do_things()
    self.assert_true(4 == 4)

  method test_for_c()=
    var c = 0
    # supposed to fail
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



# Inheritance!
test_suite TestInherit of UnitTestsNew:
  ## This will call every test defined in UnitTestsNew

  proc raises_os()=
    # This proc won't be invoked as a test
    raise newException(OSError, "Oh no! OS malfunction!")

  method test_raises()=

    # Two ways of asserting
    self.assert_raises OSError:
      self.raises_os()

    self.assert_raises(OSError, self.raises_os())


test_suite MoreInheritance of TestInherit:

  method setup()=
    # This must be called if overriding setup if you want
    # base class setup functionality. You can also call
    # self.setupTestInherit() to call the direct parent's
    # implementation
    self.setupUnitTestsNew()

    # This will make one of the tests inherited from UnitTestsNew
    # fail. This is expected.
    self.test_obj = 12345

  method test_test_obj()=
    # This method is overwritten. To call the base method,
    # simply use
    #   self.test_test_obj_UnitTestsNew()
    # However, currently this method will be run
    # IN ADDITION to the base class's method.
    # This one will pass, the other will fail
    self.assert_true(self.test_obj == 12345)

  method test_new_obj()=
    self.assert_equal(self.test_obj, 12345)


when isMainModule:
  run_tests()
