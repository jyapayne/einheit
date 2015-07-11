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
##    proc thisIsATest()=
##      self.check(1 == 1)
##      self.checkRaises(OSError, newException(OSError, "OS is exploding!"))
##
import macros
import strutils
import tables
import typetraits
when not defined(ECMAScript):
  import terminal

proc `$`*[T](ar: openarray[T]): string=
    ## Converts an array into a string
    result = "["
    if ar.len() > 0:
        result &= $ar[0]
    for i in 1..ar.len()-1:
        result &= ", " & $ar[i]
    result &= "]"
    return result

proc `$`*(s: ref object): string=
  result = "ref " & ($s[]).replace(":ObjectType", "")

proc `==`*[T](ar: openarray[T], ar2: openarray[T]): bool=
  if len(ar) != len(ar2):
    return false
  for i in countup(0, ar.len()):
    if ar[i] != ar2[i]:
      return false
  return true

type
  TestSuite = ref object of RootObj
    ## The base TestSuite
    name: string
    currentTestName: string
    testsPassed: int
    numTests: int

  TestAssertError = object of Exception
    ## checkTrue and other check_* statements will raise
    ## this exception when the condition fails
    lineNumber: int
    fileName: string
    codeSnip: string
    testName: string

# -- Methods for the TestSuite base --

method setup*(suite: TestSuite)=
  ## Base method for setup code
  discard

method tearDown*(suite: TestSuite)=
  ## Base method for setup code
  discard

method runTests*(suite: TestSuite)=
  ## Base method for running tests
  discard

# ------------------------------------

template returnException(name, testName, snip, vals, pos, posRel)=
    ## private template for raising an exception
    var
      filename = posRel.filename
      line = pos.line
    var message = "\n"
    message &= "  Condition: $2($1)\n".format(snip.replace("\n","").strip(), name)
    try:
      message &= "  Where:\n"
      for k, v in vals.pairs:
        message &= "    $1 -> $2\n".format(k, v)
    except:
      message &= "  Reason: $1\n".format(vals)

    message &= "  Location: $1; line $2".format(filename, line)

    var exc = newException(TestAssertError, message)
    exc.fileName = filename
    exc.lineNumber = line
    exc.codeSnip = snip
    exc.testName = testName
    raise exc

# ------------------------ Templates for checkion ----------------------------

template checkRaises*(self: TestSuite, error: Exception,
                       code: untyped): untyped {.immediate.}=
  ## Raises a TestAssertError when the exception "error" is
  ## not thrown in the code
  let
    pos = instantiationInfo(fullpaths=true)
    posRel = instantiationInfo()

  try:
    code
    var
      snip = "$1, $2".format(astToStr(error), astToStr(code).strip())
      vals = {astToStr(code).strip(): "No Exception Raised"}.toTable()
      testName = self.currentTestName

    returnException("checkRaises", testName, snip, vals, pos, posRel)

  except error:
    discard
  except TestAssertError:
    raise
  except Exception:
    var
      e = getCurrentException()
      snip = "$1, $2".format(astToStr(error), astToStr(code).strip())
      vals = {astToStr(code).strip(): e.name}.toTable()
      testName = self.currentTestName

    returnException("checkRaises", testName, snip, vals, pos, posRel)

template recursive(node, action): expr {.dirty.} =
  proc helper(child: NimNode): NimNode {.gensym.} =
    action
    result = child.copy()
    for c in child.children:
      if child.kind == nnkCall and c.kind == nnkDotExpr:
        continue
      result.add helper(c)
  discard helper(node)

template strRep(n: NimNode): untyped=
  $(n)

template tableEntry(n: NimNode): untyped=
  newNimNode(nnkExprColonExpr).add(n.toStrLit(), getAst(strRep(n)))

macro getSyms(code:untyped): untyped=
  var
    tableCall = newNimNode(nnkCall).add(ident("toTable"))
    tableConstr = newNimNode(nnkTableConstr)

  recursive(code):
    let ch1 = child
    if ch1.kind == nnkInfix:
      if child[1].kind == nnkIdent:
        tableConstr.add(tableEntry(child[1]))
      if child[2].kind == nnkIdent:
        tableConstr.add(tableEntry(child[2]))
    elif ch1.kind == nnkExprColonExpr:
      if child[0].kind == nnkIdent:
        tableConstr.add(tableEntry(child[0]))
      if child[1].kind == nnkIdent:
        tableConstr.add(tableEntry(child[1]))
    elif ch1.kind == nnkCall or ch1.kind == nnkCommand:
      tableConstr.add(tableEntry(ch1))
      for i in 1..<ch1.len():
        tableConstr.add(tableEntry(ch1[i]))
    elif ch1.kind == nnkDotExpr:
      tableConstr.add(tableEntry(ch1))
  if tableConstr.len() != 0:
    tableCall.add(tableConstr)
    result = tableCall
  else:
    template emptyTable()=
      newTable[string, string]()
    result = getAst(emptyTable())


template check*(self: TestSuite, code: untyped){.immediate.}=
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
    snip = astToStr(code).replace("  ", " ")

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
  ##    method setup()=
  ##      ## do setup code here
  ##      self.suiteVar = "Testing"
  ##
  ##    method testAddingString()=
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

  template importRequiredLibs()=
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

  template setNodeName(n2, procName, typeName)=
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


  template runTestsProc(self, typeName, baseMethod, typeMethod)=
    method typeMethod(self: typeName)=
      when compiles(self.baseMethod()):
        self.baseMethod()
    
    method runTests(self: typeName)=
      self.typeMethod()

  var baseMethodName = ident("runTests" & $baseName.toStrLit())
  var typeMethodName = ident("runTests" & $typeName.toStrLit())

  var runTests = getAst(runTestsProc(ident(objReference), typeName, baseMethodName, typeMethodName))

  var
    foundSetup = false
    foundTeardown = false

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

  if not foundSetup:
    template setupProc(self, typeName, setupProc)=
      method setup(self: typeName)
      method setupProc(self: typeName)

    template setupDecl(self, baseMethod)=
      method setup()=
        when compiles(self.baseMethod()):
          self.baseMethod()

    var setupProcTypename = ident("setup" & $typeName.toStrLit())
    var baseMethodName = ident("setup" & $baseName.toStrLit())
    result.add(getAst(setupProc(ident(objReference), typeName, setupProcTypename)))
    var setupBaseAst = getAst(setupDecl(ident(objReference), baseMethodName))
    body.add(setupBaseAst[0])

  if not foundTeardown:
    template teardownProc(self, typeName, tdProc)=
      method tearDown(self: typeName)
      method tdProc(self: typeName)

    template teardownDecl(self, baseMethod)=
      method tearDown()=
        when compiles(self.baseMethod()):
          self.baseMethod()

    var teardownProcTypename = ident("tearDown" & $typeName.toStrLit())
    var baseTearMethodName = ident("tearDown" & $baseName.toStrLit())
    result.add(getAst(teardownProc(ident(objReference),
                                         typeName,
                                         teardownProcTypename)))
    var teardownBaseAst = getAst(teardownDecl(ident(objReference),
                                              baseTearMethodName))
    body.add(teardownBaseAst[0])


  # Iterate over the statements, adding `self: T`
  # to the parameters of functions
  for node in body.children:
    case node.kind:
      of nnkMethodDef, nnkProcDef:
        # inject `self: T` into the arguments
        let n = copyNimTree(node)
        n.params.insert(1, newIdentDefs(ident(objReference), typeName))

        # Copy the proc or method for inheritance
        # ie: procName_ClassName()
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
        elif procName.toLower() == "teardown":
          discard
        elif procName.startswith("test"):
          let procCall = newDotExpr(ident(objReference),
                                     ident(procName & typeName))

          template setTestName(self, procName)=
            self.currentTestName = procName

          template tryBlock(self, testCall)=
            self.numTests += 1
            try:
              testCall
              styledEcho(styleBright, fgGreen, "[OK]",
                          fgWhite, "     ", self.currentTestName)
              self.testsPassed += 1
            except TestAssertError:
              let e = (ref TestAssertError)(getCurrentException())
              styledEcho(styleBright,
                          fgRed, "[Failed]",
                          fgWhite, " ", self.currentTestName, e.msg, "\n")

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

  template declareTypeExport(tname, bname)=
    type tname* = ref object of bname
  template declareType(tname, bname)=
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
  typeDecl[0][0][2][0][2] = recList

  # insert the type declaration
  result.insert(0, typeDecl)

  # insert libs needed
  result.insert(0, getAst(importRequiredLibs()))
  
  result.add(runTests)

  template addTestSuite(typeName)=
    testSuites.add(typeName())

  result.add(getAst(addTestSuite(typeName)))


proc runTests*()=
  ## The method that runs the tests. Invoke
  ## after setting up all of the tests and 
  ## usually inside a "when isMainModule" block
  for suite in testSuites:
    suite.setup()
    var numTicks = 80 - 12 - len(suite.name)
    var ticks = ""
    for i in 0..<numTicks:
      ticks &= "-"
    styledEcho(styleBright,
                fgYellow, "\n[Running]",
                fgWhite, " $1 ".format(suite.name),
                fgYellow, " ", ticks, "\n")
    suite.runTests()
    suite.tearDown()

    # Output red if tests didn't pass, green otherwise
    var color = fgGreen
    if suite.testsPassed != suite.numTests:
      color = fgRed

    var passedStr = "[" & $suite.testsPassed & "/" & $suite.numTests & "]"

    ticks = " "
    numTicks = 80 - len(passedStr) - 20 - len(suite.name)

    for i in 0..<numTicks:
      ticks &= "-"

    styledEcho(styleBright, color,
                "\n", passedStr,
                fgWhite, " tests passed for ", suite.name, ".",
                fgYellow, ticks, "\n")

