import einheit

testSuite UnitTests:
  var
    testObj: int
    testArray: array[4, int]

  proc doThings()=
    # This proc won't be invoked as a test
    self.testObj = 400
    self.check(self.testObj == 400)

  method setup()=
    self.testObj = 90
    for i in 0 ..< self.testArray.len():
      self.testArray[i] = i

  method tearDown()=
    self.testObj = 0

  method testForB()=
    var b = 4
    self.doThings()
    self.check(b == 4)

  method testArrayAssert()=
    self.check(self.testArray == [0,1,2])

  method testForC()=
    var c = 0
    # supposed to fail
    self.check(c == 1)


testSuite UnitTestsNew:
  var
    testObj: int

  method setup()=
    self.testObj = 90

  method tearDown()=
    self.testObj = 0

  method testTestObj()=
    self.check(self.testObj == 90)

  method testStuff()=
    self.check("Stuff" == "Stuff")

  proc returnTrue(): bool=
    return false

  method testMore()=
    var more = 23
    self.check(more == 1)

  method testMoreMore()=
    self.check(self.returnTrue())

# Inheritance!
testSuite TestInherit of UnitTestsNew:
  ## This will call every test defined in UnitTestsNew

  proc raisesOs()=
    # This proc won't be invoked as a test
    raise newException(SystemError, "Oh no! OS malfunction!")

  method testRaises()=

    # Two ways of checking
    self.checkRaises OSError:
      self.raisesOs()

    self.checkRaises(OSError, self.raisesOs())


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
    self.check(self.testObj == 12345)

  method testNewObj()=
    self.check(self.testObj == 12345)

  proc doStuff(arg: int, arg2: string): string=
    result = $arg & arg2

  method testComplex()=

    type
      TestObj = ref object
        t: int
      Person = tuple[name: string, age: int]

    proc `==`(d: TestObj, d2: TestObj): bool=
      return d.t == d2.t

    var
      a = 5
      s = "stuff"
      y = 45

      t: Person = (name: "Peter", age: 30)
      r: Person = (name: "P", age: 3)
      d = TestObj(t: 3)
      k = TestObj(t: 30)

    self.check(t != r)
    self.check(d == k)

    self.check(self.doStuff(a, s) == "5stuff" and self.doStuff(a, self.doStuff(a, self.doStuff(y, s))) == "something?")


when isMainModule:
  runTests()
