## :Author: Joey Payne
## This module is an alternate implementation of
## the unittest module in Nim. Inspired by the python
## unit test module.
##
## Example:
##
## .. code:: nim
##
##  testSuite UnitTests:
##    proc thisIsATest() =
##      self.check(1 == 1)
##      self.checkRaises(OSError, newException(OSError, "OS is exploding!"))
##
import macros
import unicode except split
import strutils except toLower
import tables
import typetraits
when defined(ECMAScript):
  const noColors = true
else:
  const noColors = defined(noColors)
  import terminal
import einheit/utils

# ----------------- Helper Procs and Macros -----------------------------------

proc `$`*[T](ar: openarray[T]): string =
    ## Converts an array into a string
    result = "["
    if ar.len() > 0:
        result &= $ar[0]
    for i in 1..ar.len()-1:
        result &= ", " & $ar[i]
    result &= "]"

proc typeToStr*[T](some:typedesc[T]): string = name(T)

template tupleObjToStr(obj): string {.dirty.} =
  var res = typeToStr(type(obj))
  template helper(n) {.gensym.} =
    res.add("(")
    var firstElement = true
    for name, value in n.fieldPairs():
      when compiles(value):
        if not firstElement:
          res.add(", ")
        res.add(name)
        res.add(": ")
        when (value is object or value is tuple):
          when (value is tuple):
            res.add("tuple " & typeToStr(type(value)))
          else:
            res.add(typeToStr(type(value)))
          helper(value)
        elif (value is string):
          res.add("\"" & $value & "\"")
        else:
          res.add($value)
        firstElement = false
    res.add(")")
  helper(obj)
  res

proc `$`*(s: ref object): string =
  result = "ref " & tupleObjToStr(s[]).replace(":ObjectType", "")

proc objToStr*[T: object](obj: var T): string =
  tupleObjToStr(obj)

proc objToStr*[T: tuple](obj: T): string =
  result = "tuple " & tupleObjToStr(obj)

macro toString*(obj: typed): untyped =
  ## this macro is to work around not being
  ## able to override system.`$`
  ##
  ## Basically, I want to use my proc to print
  ## objects and tuples, but the regular $ for
  ## everything else
  let kind = obj.getType().typeKind
  case kind:
    of ntyTuple, ntyObject:
      template toStrAst(obj): string =
        einheit.objToStr(obj)
      result = getAst(toStrAst(obj))
    of ntyString:
      template toStrAst(obj): string =
        "\"" & $(obj) & "\""
      result = getAst(toStrAst(obj))
    else:
      template toStrAst(obj): string =
        $(obj)
      result = getAst(toStrAst(obj))

# ----------------------- Test Suite Types ------------------------------------
type
  TestSuite* = ref object of RootObj
    ## The base TestSuite
    name: string
    currentTestName: string
    testsPassed: int
    numTests: int
    lastTestFailed: bool

  TestAssertError = object of Exception
    ## check and other check* statements will raise
    ## this exception when the condition fails
    lineNumber: int
    fileName: string
    codeSnip: string
    testName: string
    checkFuncName: string
    valTable: Table[string, string]


# -- Methods for the TestSuite base --

method setup*(suite: TestSuite) {.base.} =
  ## Base method for setup code
  discard

method tearDown*(suite: TestSuite) {.base.} =
  ## Base method for tearDown code
  discard

method runTests*(suite: TestSuite) {.base.} =
  ## Base method for running tests
  discard

# ------------------------------------

template returnException(name, tName, snip, vals, pos, posRel) =
    ## private template for raising an exception
    var
      filename = posRel.filename
      line = pos.line
    var message = "\l"
    message &= "  Condition: $2($1)\l".format(snip, name)
    message &= "  Where:\l"
    for k, v in vals.pairs:
      message &= "    $1 -> $2\l".format(k, v)

    message &= "  Location: $1; line $2".format(filename, line)

    var exc = newException(TestAssertError, message)
    exc.fileName = filename
    exc.lineNumber = line
    exc.codeSnip = snip
    exc.testName = tName
    exc.valTable = vals
    exc.checkFuncName = name
    raise exc

# ------------------------ Templates for checking ----------------------------

template checkRaises*(self: untyped, error: untyped,
                       code: untyped): untyped =
  ## Raises a TestAssertError when the exception "error" is
  ## not thrown in the code
  let
    pos = instantiationInfo(fullpaths=true)
    posRel = instantiationInfo()

  try:
    code
    let
      codeStr = astToStr(code).split().join(" ")
      snip = "$1, $2".format(astToStr(error), codeStr)
      vals = [(codeStr, "No Exception Raised")].toTable()
      testName = self.currentTestName
    returnException("checkRaises", testName, snip, vals, pos, posRel)

  except error:
    discard
  except TestAssertError:
    raise
  except Exception:
    let
      e = getCurrentException()
      codeStr = astToStr(code).split().join(" ")
      snip = "$1, $2".format(astToStr(error), codeStr)
      vals = [(codeStr, $e.name)].toTable()
      testName = self.currentTestName

    returnException("checkRaises", testName, snip, vals, pos, posRel)

template recursive(node, action): untyped {.dirty.} =
  ## recursively iterate over AST nodes and perform an
  ## action on them
  proc helper(child: NimNode): NimNode {.gensym.} =
    action
    result = child.copy()
    for c in child.children:
      if child.kind == nnkCall and c.kind == nnkDotExpr:
        # ignore dot expressions that are also calls
        continue
      result.add helper(c)
  discard helper(node)

proc getNode(nodeKind: NimNodeKind, node: NimNode): NimNode =
  ## Gets the first node with nodeKind
  var stack: seq[NimNode] = @[node]

  while stack.len() > 0:
    let newNode = stack.pop()
    for i in 0 ..< newNode.len():
      let child = newNode[i]
      if child.kind == nodeKind:
        return child
      else:
        stack.add(child)

  return newEmptyNode()

template strRep(n: NimNode): untyped =
  toString(n)

template tableEntry(n: NimNode): untyped =
  newNimNode(nnkExprColonExpr).add(n.toStrLit(), getAst(strRep(n)))

macro getSyms(code:untyped): untyped =
  ## This macro gets all symbols and values of an expression
  ## into a table
  ##
  ## Table[string, string] -> symbolName, value
  ##
  var
    tableCall = newNimNode(nnkCall).add(ident("toTable"))
    tableConstr = newNimNode(nnkTableConstr)

  recursive(code):
    let ch1 = child
    case ch1.kind:
      of nnkInfix:
        if child[1].kind == nnkIdent:
          tableConstr.add(tableEntry(child[1]))
        if child[2].kind == nnkIdent:
          tableConstr.add(tableEntry(child[2]))
      of nnkExprColonExpr:
        if child[0].kind == nnkIdent:
          tableConstr.add(tableEntry(child[0]))
        if child[1].kind == nnkIdent:
          tableConstr.add(tableEntry(child[1]))
      of nnkCall, nnkCommand:
        tableConstr.add(tableEntry(ch1))
        if ch1.len() > 0 and ch1[0].kind == nnkDotExpr:
          tableConstr.add(tableEntry(ch1[0][0]))
        for i in 1 ..< ch1.len():
          tableConstr.add(tableEntry(ch1[i]))
      of nnkDotExpr:
        tableConstr.add(tableEntry(ch1))
      else:
        discard
  if tableConstr.len() != 0:
    tableCall.add(tableConstr)
    result = tableCall
  else:
    template emptyTable() =
      initTable[string, string]()
    result = getAst(emptyTable())

template check*(self: untyped, code: untyped)=
  ## Assertions for tests
  if not code:
    # These need to be here to capture the actual info
    let
      pos = instantiationInfo(fullpaths=true)
      posRel = instantiationInfo()

    var
      snip = ""
      testName = self.currentTestName

    var vals = getSyms(code)
    # get ast string with extra spaces ignored
    snip = astToStr(code).split().join(" ")

    returnException("check", testName, snip, vals, pos, posRel)

# -----------------------------------------------------------------------------


# A list to hold all test suites that are created
var testSuites: seq[TestSuite] = @[]

macro testSuite*(head: untyped, body: untyped): untyped =
  ## Compile-time macro that allows a user to define tests and run them
  ##
  ## Methods are used for inheritance, so if you want to derive a test
  ## suite, then you have to make sure the base suite uses methods
  ## for the tests that you want to derive.
  ##
  ## If you don't want inheritance, you can just use procs.
  ##
  ## A special proc/method is called setup(). The macro will inject
  ## this if it doesn't exist and it will be called before running
  ## the test suite.
  ##
  ## Test methods/procs to be run are prefixed with "test" in the
  ## method/proc name. This is so that you can write tests that call
  ## procs that do other things and won't be run as a test.
  ##
  ## For each suite method/proc, an implicit variable called "self"
  ## is added. This lets you access the testSuite in an OO kind
  ## of way.
  ##
  ## Usage:
  ##
  ## .. code:: nim
  ##
  ##  testSuite SuiteName of TestSuite:
  ##
  ##    var
  ##      suiteVar: string
  ##
  ##    method setup() =
  ##      ## do setup code here
  ##      self.suiteVar = "Testing"
  ##
  ##    method testAddingString() =
  ##      ## adds a string to the suiteVar
  ##      self.suiteVar &= " 123"
  ##      self.check(self.suiteVar == "Testing 123")
  ##
  ##  when isMainModule:
  ##    einheit.runTests()
  ##


  # object reference name inside methods.
  # ie: self, self
  let objReference = "self"
  var exportClass: bool = false

  template importRequiredLibs() =
    import strutils
    import tables
    import typetraits
    when not defined(ECMAScript):
      import terminal

  var typeName, baseName: NimNode

  if head.kind == nnkIdent:
    # `head` is expression `typeName`
    # echo head.treeRepr
    # --------------------
    # Ident !"UnitTests"
    typeName = head

  elif head.kind == nnkInfix and $head[0] == "of":
    # `head` is expression `typeName of baseClass`
    # echo head.treeRepr
    # --------------------
    # Infix
    # Ident !"of"
    # Ident !"UnitTests"
    # Ident !"RootObj"
    typeName = head[1]
    baseName = head[2]

  elif head.kind == nnkInfix and $head[0] == "*" and $head[1] == "of":
    # echo head.treeRepr
    # -----------
    # Infix
    #  Ident !"*"
    #  Ident !"UnitTests
    #  Prefix
    #  Ident !"of"
    #  Ident !"RootObj"
    exportClass = true
    typeName = head[1]
    baseName = head[2][1]
  elif head.kind == nnkInfix and $head[0] == "*":
    exportClass = true
    typeName = head[1]
  else:
    quit "Invalid node: " & head.lispRepr


  # echo treeRepr(body)
  # --------------------
  # StmtList
  # VarSection
  #   IdentDefs
  #     Ident !"name"
  #     Ident !"string"
  #     Empty
  #   IdentDefs
  #     Ident !"age"
  #     Ident !"int"
  #     Empty
  # MethodDef
  #   Ident !"vocalize"
  #   Empty
  #   Empty
  #   FormalParams
  #     Ident !"string"
  #   Empty
  #   Empty
  #   StmtList
  #     StrLit ...
  # MethodDef
  #   Ident !"ageHumanYrs"
  #   Empty
  #   Empty
  #   FormalParams
  #     Ident !"int"
  #   Empty
  #   Empty
  #   StmtList
  #     DotExpr
  #       Ident !"self"
  #       Ident !"age"

  # create a new stmtList for the result
  result = newStmtList()

  # var declarations will be turned into object fields
  var recList = newNimNode(nnkRecList)

  # add a super function to simulate OOP
  # inheritance tree (Doesn't do what is expected because of dynamic binding)
  #if not isNil(`baseName`):
  #    var super = quote do:
  #        proc super(self: `typeName`): `baseName`=
  #          return `baseName`(self)
  #   result.add(super)

  template setNodeName(n2, procName, typeName) =
    if n2.name.kind == nnkIdent:
      procName = $(n2.name.toStrLit())
      n2.name = ident(procName & typeName)
    elif n2.name.kind == nnkPostFix:
      if n2.name[1].kind == nnkIdent:
        procName = $(n2.name[1].toStrLit())
        n2.name[1] = ident(procName & typeName)
      elif n2.name[1].kind == nnkAccQuoted:
        procName = $(n2.name[1][0].toStrLit())
        n2.name[1][0] = ident(procName & typeName)
    elif n2.name.kind == nnkAccQuoted:
      procName = $(n2.name[0].toStrLit())
      n2.name[0] = ident(procName & typeName)
    result.add(n2)


  template runTestsProc(self, typeName, baseMethod, typeMethod) =
    method typeMethod(self: typeName) {.base.} =
      when compiles(self.baseMethod()):
        self.baseMethod()

    method runTests(self: typeName) =
      self.typeMethod()

  var baseMethodName = ident("runTests" & $baseName.toStrLit())
  var typeMethodName = ident("runTests" & $typeName.toStrLit())

  var runTests = getAst(
    runTestsProc(
      ident(objReference), typeName,
      baseMethodName, typeMethodName
    )
  )

  var
    foundSetup = false
    foundTeardown = false

  # {.push warning[UseBase]: off.}
  result.add(
    newNimNode(nnkPragma).add(
      ident("push"),
      newNimNode(nnkExprColonExpr).add(
        newNimNode(nnkBracketExpr).add(
          ident("warning"),
          ident("UseBase")
        ),
        ident("off")
      )
    )
  )

  # Make forward declarations so that function order
  # does not matter, just like in real OOP!
  for node in body.children:
    case node.kind:
      of nnkMethodDef, nnkProcDef:
        # inject `self: T` into the arguments
        let n = copyNimTree(node)
        n.params.insert(1, newIdentDefs(ident(objReference), typeName))
        # clear the body so we only get a
        # declaration
        n.body = newEmptyNode()
        result.add(n)

        # forward declare the inheritable method
        let n2 = copyNimTree(n)
        let typeName = $(typeName.toStrLit())
        var procName = ""

        setNodeName(n2, procName, typeName)

        if procName.toLower() == "setup":
          foundSetup = true
        if procName.toLower() == "teardown":
          foundTeardown = true
      else:
        discard

  # {.pop.}
  result.add(
    newNimNode(nnkPragma).add(
      ident("pop")
    )
  )

  if not foundSetup:
    template setupProc(self, typeName, setupProc) =
      method setup(self: typeName)
      method setupProc(self: typeName) {.base.}

    template setupDecl(self, baseMethod) =
      method setup() =
        when compiles(self.baseMethod()):
          self.baseMethod()


    var setupProcTypename = ident("setup" & $typeName.toStrLit())
    var baseMethodName = ident("setup" & $baseName.toStrLit())
    result.add(getAst(setupProc(ident(objReference), typeName, setupProcTypename)))
    body.add(getAst(setupDecl(ident(objReference), baseMethodName)))

  if not foundTeardown:
    template teardownProc(self, typeName, tdProc) =
      method tearDown(self: typeName)
      method tdProc(self: typeName) {.base.}

    template teardownDecl(self, baseMethod) =
      method tearDown() =
        when compiles(self.baseMethod()):
          self.baseMethod()

    var teardownProcTypename = ident("tearDown" & $typeName.toStrLit())
    var baseTearMethodName = ident("tearDown" & $baseName.toStrLit())
    result.add(getAst(teardownProc(ident(objReference),
                                         typeName,
                                         teardownProcTypename)))
    body.add(getAst(teardownDecl(ident(objReference),
                    baseTearMethodName)))

  template setTestName(self, procName) =
    self.currentTestName = procName

  template tryBlock(self, testCall) =
    self.numTests += 1
    try:
      testCall
      when defined(quiet):
        when noColors:
          stdout.write(".")
        else:
          setForegroundColor(fgGreen)
          writeStyled(".", {styleBright})
          setForegroundColor(fgWhite)
      else:
        var okStr = "[OK]"
        if self.lastTestFailed:
          okStr = "\l" & okStr

        when not noColors:
          styledEcho(styleBright, fgGreen, okStr,
                     fgWhite, "     ", self.currentTestName)
        else:
          echo "$1     $2".format(okStr, self.currentTestName)

      self.testsPassed += 1
      self.lastTestFailed = false
    except TestAssertError:
      let e = (ref TestAssertError)(getCurrentException())

      when defined(quiet):
        when noColors:
          stdout.write("F")
        else:
          setForegroundColor(fgRed)
          writeStyled("F", {styleBright})
          setForegroundColor(fgWhite)
      else:
        when not noColors:
          styledEcho(styleBright,
                     fgRed, "\l[Failed]",
                     fgWhite, " ", self.currentTestName)
        else:
          echo "\l[Failed] $1".format(self.currentTestName)

        let
          name = e.checkFuncName
          snip = e.codeSnip
          line = e.lineNumber
          filename = e.fileName
          vals = e.valTable

        when not noColors:
          styledEcho(styleDim, fgWhite, "  Condition: $2($1)\l".format(snip, name), "  Where:")
          for k, v in vals.pairs:
            styledEcho(styleDim, fgCyan, "    ", k,
                       fgWhite, " -> ",
                       fgGreen, v)
          styledEcho(styleDim, fgWhite, "  Location: $1; line $2".format(filename, line))
        else:
          echo "  Condition: $2($1)".format(snip, name)
          echo "  Where:"
          for k, v in vals.pairs:
            echo "    ", k, " -> ", v

          echo "  Location: $1; line $2".format(filename, line)
      self.lastTestFailed = true

  # Iterate over the statements, adding `self: T`
  # to the parameters of functions
  for node in body.children:
    case node.kind:
      of nnkMethodDef, nnkProcDef:
        # inject `self: T` into the arguments
        let n = copyNimTree(node)
        n.params.insert(1, newIdentDefs(ident(objReference), typeName))

        # Copy the proc or method for inheritance
        # ie: procNameClassName()
        let n2 = copyNimTree(node)
        n2.params.insert(1, newIdentDefs(ident(objReference), typeName))

        let typeName = $(typeName.toStrLit())
        var procName = $(n2.name.toStrLit())
        var isAssignment = procName.contains("=")

        setNodeName(n2, procName, typeName)

        if procName.toLower() == "setup":
          let dotName = newDotExpr(ident(objReference), ident("name"))
          let setName = newAssignment(dotName, newLit(typeName))
          n2.body.add(setName)
          let dotRan = newDotExpr(ident(objReference), ident("lastTestFailed"))
          let setRan = newAssignment(dotRan, ident("true"))
          n2.body.add(setRan)
        elif procName.toLower() == "teardown":
          discard
        elif procName.startswith("test"):
          let procCall = newDotExpr(ident(objReference),
                                     ident(procName & typeName))

          runTests[0][6].add(getAst(setTestName(ident(objReference), procName)))
          runTests[0][6].add(getAst(tryBlock(ident(objReference), procCall)))

        # simply call the class method from here
        # proc procName=
        #    procName_ClassName()
        var p: seq[NimNode] = @[]
        for i in 1..n.params.len-1:
          p.add(n.params[i][0])
        if isAssignment:
          let dot = newDotExpr(ident(objReference), ident(procName & typeName))
          n.body = newStmtList(newAssignment(dot, p[1]))
        else:
          n.body = newStmtList(newCall(procName & typeName, p))

        result.add(n)

      of nnkVarSection:
        # variables get turned into fields of the type.
        for n in node.children:
          recList.add(n)
      else:
        result.add(node)

  # The following prints out the AST structure:
  #
  # import macros
  # dumptree:
  # type X = ref object of Y
  #   z: int
  # --------------------
  # TypeSection
  # TypeDef
  #   Ident !"X"
  #   Empty
  #   RefTy
  #     ObjectTy
  #       Empty
  #       OfInherit
  #         Ident !"Y"
  #       RecList
  #         IdentDefs
  #           Ident !"z"
  #           Ident !"int"
  #           Empty

  var typeDecl: NimNode

  template declareTypeExport(tname, bname) =
    type tname* = ref object of bname
  template declareType(tname, bname) =
    type tname = ref object of bname

  if baseName == nil:
    if exportClass:
      typeDecl = getAst(declareTypeExport(typeName, TestSuite))
    else:
      typeDecl = getAst(declareType(typeName, TestSuite))
  else:
    if exportClass:
      typeDecl = getAst(declareTypeExport(typeName, baseName))
    else:
      typeDecl = getAst(declareType(typeName, baseName))

  # Inspect the tree structure:
  #
  # echo typeDecl.treeRepr
  # --------------------
  # StmtList
  #   TypeSection
  #     TypeDef
  #       Ident !"UnitTests"
  #       Empty
  #       RefTy
  #         ObjectTy
  #           Empty
  #           OfInherit
  #             Ident !"RootObj"
  #           Empty   <= We want to replace this

  var objTyNode = getNode(nnkObjectTy, typeDecl)
  objTyNode[2] = recList

  # insert the type declaration
  result.insert(0, typeDecl)

  # insert libs needed
  result.insert(0, getAst(importRequiredLibs()))

  result.add(runTests)

  template addTestSuite(typeName) =
    testSuites.add(typeName())

  result.add(getAst(addTestSuite(typeName)))


proc printRunning(suite: TestSuite) =
  let termSize = getTermSize()
  var
    numTicks = termSize[1]
    ticks = ""

  for i in 0..<numTicks:
    ticks &= "-"

  when not defined(quiet):
    when not noColors:
      styledEcho(styleBright,
                  fgYellow, "\l"&ticks,
                  fgYellow, "\l\l[Running]",
                  fgWhite, " $1 ".format(suite.name))
    else:
      echo "\l$1\l".format(ticks)
      echo "[Running] $1".format(suite.name)


proc printPassedTests(suite: TestSuite) =
  when not noColors:
    # Output red if tests didn't pass, green otherwise
    var color = fgGreen

    if suite.testsPassed != suite.numTests:
      color = fgRed

  var passedStr = "[" & $suite.testsPassed & "/" & $suite.numTests & "]"

  when not defined(quiet):
    when not noColors:
      styledEcho(styleBright, color,
                  "\l", passedStr,
                  fgWhite, " tests passed for ", suite.name, ".")
    else:
      echo "\l$1 tests passed for $2.".format(passedStr, suite.name)

proc printSummary(totalTestsPassed: int, totalTests: int) =
  when not noColors:
    var summaryColor = fgGreen

    if totalTestsPassed != totalTests:
      summaryColor = fgRed

  var passedStr = "[" & $totalTestsPassed & "/" & $totalTests & "]"

  when defined(quiet):
    when not noColors:
      styledEcho(styleBright, summaryColor,
                 "\l\l", passedStr,
                 fgWhite, " tests passed.")
    else:
      echo "\l\l$1 tests passed.".format(passedStr)
  else:

    let termSize = getTermSize()

    var
      ticks = ""
      numTicks = termSize[1]

    for i in 0..<numTicks:
      ticks &= "-"

    when not noColors:
      styledEcho(styleBright,
                 fgYellow, "\l$1\l".format(ticks),
                 fgYellow, "\l[Summary]")

      styledEcho(styleBright, summaryColor,
                  "\l  ", passedStr,
                  fgWhite, " tests passed.")
    else:
      echo "\l$1\l".format(ticks)
      echo "\l[Summary]"
      echo "\l  $1 tests passed.".format(passedStr)

proc runTests*() =
  ## The method that runs the tests. Invoke
  ## after setting up all of the tests and
  ## usually inside a "when isMainModule" block
  var
    totalTests = 0
    totalTestsPassed = 0

  when defined(quiet):
    echo ""

  for suite in testSuites:
    suite.setup()

    suite.printRunning()

    suite.runTests()

    suite.tearDown()

    suite.printPassedTests()

    totalTests += suite.numTests
    totalTestsPassed += suite.testsPassed

  printSummary(totalTestsPassed, totalTests)
