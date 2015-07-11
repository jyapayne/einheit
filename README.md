# einheit

Einheit means unit in German.

Einheit is a Nim unit testing library inspired by Python's unit tests. Nim's unittest library is good, but I wanted something a little more "Nim" feeling. I also really like Python's unittest module and thought it would be nice to have something similar in Nim. Also, unittest doesn't have much documentation on how to use it, and it's pretty bare bones, so I wanted a little more functionality and documentation.

The benefit of the macro style I chose means that you can document your tests nicely as well :)

### Description
testSuite is a compile-time macro that allows a user to easily define tests and run them.

Methods are used for inheritance, so if you want to derive a test suite, then you have to make sure the base suite uses methods for the tests that you want to derive.

If you don't want inheritance, you can just use procs.

Two special methods/procs are called setup() and tearDown(). The macro will inject these methods/procs if they don't exist and they will be called before and after running the test suite, respectively.

Test methods/procs to be run are prefixed with "test" in the method/proc name. This is so that you can write tests that call procs that do other things and won't be run as a test.

For each suite method/proc, an implicit variable called "self" is added. This lets you access the testSuite in an OO kind of way.

On failure, the macro gathers names and values of *all* arguments and functions and prints them out. It's really useful for debugging!

### Installation

Install with nimble!

```bash
nimble install einheit
```

### Usage

```nim
import einheit

testSuite SuiteName of TestSuite:

  var
    suiteVar: string
    testObj: int

  method setup()=
    ## do setup code here
    self.suiteVar = "Testing"
    self.testObj = 90

  method tearDown()=
    ## do tear down code here
    self.suiteVar = nil
    self.testObj = 0

  method testAddingString()=
    ## adds a string to the suiteVar
    self.suiteVar &= " 123"
r   self.check(self.suiteVar == "Testing 123")

  proc raisesOs()=
    # This proc won't be invoked as a test, it must begin with "test" in lowercase
    raise newException(OSError, "Oh no! OS malfunction!")
  
  method testRaises()=
    # Two ways of checking
    self.checkRaises OSError:
      self.raisesOs()

    self.checkRaises(OSError, self.raisesOs())

  method testTestObj()=
    self.check(self.testObj == 90)

  method testMoreMore()=
    self.check("String" == "String")

  when isMainModule:
    einheit.runTests()
```

You can also find examples in the [test.nim](test.nim) file, including inheritance.


Output of running

```bash
nim c -r test.nim
```

is this:

```
[Running] UnitTests  -----------------------------------------------------------

[OK]     testForB
[Failed] testArrayAssert
  Condition: check(self.testArray == [0, 1, 2])
  Where:
    self.testArray -> [0, 1, 2, 3]
  Location: test.nim; line 27

[Failed] testForC
  Condition: check(c == 1)
  Where:
    c -> 0
  Location: test.nim; line 32


[1/3] tests passed for UnitTests. ----------------------------------------------


[Running] UnitTestsNew  --------------------------------------------------------

[OK]     testTestObj
[OK]     testStuff
[Failed] testMore
  Condition: check(more == 1)
  Where:
    more -> 23
  Location: test.nim; line 56

[Failed] testMoreMore
  Condition: check(self.returnTrue())
  Where:
    self.returnTrue() -> false
  Location: test.nim; line 59


[2/4] tests passed for UnitTestsNew. -------------------------------------------


[Running] TestInherit  ---------------------------------------------------------

[OK]     testTestObj
[OK]     testStuff
[Failed] testMore
  Condition: check(more == 1)
  Where:
    more -> 23
  Location: test.nim; line 56

[Failed] testMoreMore
  Condition: check(self.returnTrue())
  Where:
    self.returnTrue() -> false
  Location: test.nim; line 59

[Failed] testRaises
  Condition: checkRaises(OSError, self.raisesOs())
  Where:
    self.raisesOs() -> Exception
  Location: test.nim; line 72


[2/5] tests passed for TestInherit. --------------------------------------------


[Running] MoreInheritance  -----------------------------------------------------

[Failed] testTestObj
  Condition: check(self.testObj == 90)
  Where:
    self.testObj -> 12345
  Location: test.nim; line 46

[OK]     testStuff
[Failed] testMore
  Condition: check(more == 1)
  Where:
    more -> 23
  Location: test.nim; line 56

[Failed] testMoreMore
  Condition: check(self.returnTrue())
  Where:
    self.returnTrue() -> false
  Location: test.nim; line 59

[Failed] testRaises
  Condition: checkRaises(OSError, self.raisesOs())
  Where:
    self.raisesOs() -> Exception
  Location: test.nim; line 72

[OK]     testTestObj
[OK]     testNewObj
[Failed] testComplex
  Condition: check(self.doStuff(a, s) == "5stuff" and  self.doStuff(a, self.doStuff(a, self.doStuff(y, s))) == "something?")
  Where:
    self.doStuff(a, s) -> 5stuff
    a -> 5
    self.doStuff(a, self.doStuff(a, self.doStuff(y, s))) -> 5545stuff
    y -> 45
    s -> stuff
    self.doStuff(y, s) -> 45stuff
    self.doStuff(a, self.doStuff(y, s)) -> 545stuff
  Location: test.nim; line 134


[3/8] tests passed for MoreInheritance. ----------------------------------------
```

Notice that on failure, the test runner gives some useful information about the test in question. This is useful for determining why the test failed.
