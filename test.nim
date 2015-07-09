import einheit

testSuite UnitTests:
  var
    testObj: int
    testArray: array[4, int]

  proc doThings()=
    # This proc won't be invoked as a test
    self.testObj = 400
    self.assert(self.testObj == 400)

  method setup()=
    self.testObj = 90
    for i in 0 ..< self.testArray.len():
      self.testArray[i] = i

  method tearDown()=
    self.testObj = 0

  method testForB()=
    var b = 4
    self.doThings()
    self.assert(b == 4)

  method testArrayAssert()=
    self.assert(self.testArray == [0,1,2])

  method testForC()=
    var c = 0
    # supposed to fail
    self.assert(c == 1)


testSuite UnitTestsNew:
  var
    testObj: int

  method setup()=
    self.testObj = 90

  method tearDown()=
    self.testObj = 0

  method testTestObj()=
    self.assert(self.testObj == 90)

  method testStuff()=
    self.assert("Stuff" == "Stuff")

  proc returnTrue(): bool=
    return false

  method testMore()=
    var more = 23
    self.assert(more == 1)

  method testMoreMore()=
    self.assert(self.returnTrue())

# Inheritance!
testSuite TestInherit of UnitTestsNew:
  ## This will call every test defined in UnitTestsNew

  proc raisesOs()=
    # This proc won't be invoked as a test
    raise newException(OSError, "Oh no! OS malfunction!")

  method testRaises()=

    # Two ways of asserting
    self.assertRaises OSError:
      self.raisesOs()

    self.assertRaises(OSError, self.raisesOs())


testSuite MoreInheritance of TestInherit:

  method setup()=
    # This must be called if overriding setup if you want
    # base class setup functionality. You can also call
    # self.setupTestInherit() to call the direct parent's
    # implementation
    self.setupUnitTestsNew()

    # This will make one of the tests inherited from UnitTestsNew
    # fail. This is expected.
    self.testObj = 12345

  method tearDown()=
    # Calling the direct parent's tearDown method
    self.tearDownTestInherit()
    self.testObj = 0

  method testTestObj()=
    # This method is overwritten. To call the base method,
    # simply use
    #   self.testTestObj_UnitTestsNew()
    # However, currently this method will be run
    # IN ADDITION to the base class's method.
    # This one will pass, the other will fail
    self.assert(self.testObj == 12345)

  method testNewObj()=
    self.assert(self.testObj == 12345)


when isMainModule:
  runTests()
