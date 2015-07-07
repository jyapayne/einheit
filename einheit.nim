## :Author: Joey Payne
## This module is an alternate implementation of 
## the unittest module in Nim. Inspired by the python
## unit test module.
##
## Example:
##
## .. code:: nim
##
##  test_suite UnitTests:
##    proc this_is_a_test()=
##      self.assert_equals(1, 1)
##      self.assert_true(2 != 3)
##      self.assert_false(3 == 4)
##      self.assert_raises(OSError, newException(OSError, "OS is exploding!"))
##


import macros
import strutils
when not defined(ECMAScript):
  import terminal

type
  TestSuite = ref object of RootObj
    name: string
    current_test_name: string
    tests_passed: int
    num_tests: int

  TestAssertError = object of Exception
    line_number: int
    file_name: string
    code_snip: string
    test_name: string

# Methods for the TestSuite base

method setup*(suite: TestSuite)=
  discard

method run_tests*(suite: TestSuite)=
  discard

template return_exception(name, test_name, snip, vals)=
    let pos = instantiationInfo(fullpaths=true)
    let pos_rel = instantiationInfo()
    var
      filename = pos_rel.filename
      line = pos.line
    var message = "\n"
    message &= "  Condition: $2($1)\n".format(snip.replace("\n","").strip(), name)
    message &= "  Reason: $1\n".format(vals)
    message &= "  Location: $1; line $2".format(filename, line)

    var exc = newException(TestAssertError, message)
    exc.file_name = filename
    exc.line_number = line
    exc.code_snip = snip
    exc.test_name = test_name
    raise exc

template assert_equal*(self: TestSuite, lhs: untyped, rhs: untyped): untyped {.immediate.}=
  if (lhs) != (rhs):
    var snip = astToStr(lhs) & ", " & astToStr(rhs)

    var
      vals = "$3 == $1; $1 != $2".format(lhs, rhs, astToStr(lhs))
      test_name = self.current_test_name

    return_exception("assert_true", test_name, snip, vals)

template assert_true*(self: TestSuite, code: untyped): untyped {.immediate.}=
  if not code:
    var snip = astToStr(code)

    var
      vals = "($1) == $2".format(snip, code)
      test_name = self.current_test_name

    return_exception("assert_true", test_name, snip, vals)

template assert_false*(self: TestSuite, code: untyped): untyped {.immediate.}=
  if code:
    var snip = astToStr(code)

    var
      vals = "($1) == $2".format(snip, code)
      test_name = self.current_test_name

    return_exception("assert_false", test_name, snip, vals)


template assert_raises*(self: TestSuite, error: untyped, code: untyped): untyped {.immediate.}=
  try:
    code
    var
      snip = astToStr(code)
      vals = "No Exception Raised"
      test_name = self.current_test_name

    return_exception("assert_raises", test_name, snip, vals)

  except error:
    discard
  except TestAssertError:
    raise
  except Exception:
    var
      snip = astToStr(code)
      vals = "Exception != $1".format(astToStr(error))
      test_name = self.current_test_name

    return_exception("assert_raises", test_name, snip, vals)

    discard

# A list to hold all test suites
var test_suites: seq[TestSuite] = @[]

macro test_suite*(head: untyped, body: untyped): untyped =
  
  # object reference name inside methods.
  # ie: self, self
  let obj_reference = "self"
  var export_class: bool = false

  template import_required_libs()=
    import strutils
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
    export_class = true
    typeName = head[1]
    baseName = head[2][1]
  elif head.kind == nnkInfix and $head[0] == "*":
    export_class = true
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
  #   Ident !"age_human_yrs"
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

  template set_node_name(n2, proc_name, type_name)=
    if n2.name.kind == nnkIdent:
      proc_name = $(n2.name.toStrLit())
      n2.name = ident(proc_name & type_name)
    elif n2.name.kind == nnkPostFix:
      if n2.name[1].kind == nnkIdent:
        proc_name = $(n2.name[1].toStrLit())
        n2.name[1] = ident(proc_name & type_name)
      elif n2.name[1].kind == nnkAccQuoted:
        proc_name = $(n2.name[1][0].toStrLit())
        n2.name[1][0] = ident(proc_name & type_name)
    elif n2.name.kind == nnkAccQuoted:
      proc_name = $(n2.name[0].toStrLit())
      n2.name[0] = ident(proc_name & type_name)
    result.add(n2)


  template run_tests_proc(self, typeName, base_method, type_method)=
    method type_method(self: typeName)=
      when compiles(self.base_method()):
        self.base_method()
    
    method run_tests(self: typeName)=
      self.type_method()

  var base_method_name = ident("run_tests" & $baseName.toStrLit())
  var type_method_name = ident("run_tests" & $typeName.toStrLit())

  var run_tests = getAst(run_tests_proc(ident(obj_reference), typeName, base_method_name, type_method_name))

  var found_setup = false

  # Make forward declarations so that function order
  # does not matter, just like in real OOP!
  for node in body.children:
    case node.kind:
      of nnkMethodDef, nnkProcDef:
        # inject `self: T` into the arguments
        let n = copyNimTree(node)
        n.params.insert(1, newIdentDefs(ident(obj_reference), typeName))
        # clear the body so we only get a
        # declaration
        n.body = newEmptyNode()
        result.add(n)

        # forward declare the inheritable method
        let n2 = copyNimTree(n)
        let type_name = $(typeName.toStrLit())
        var proc_name = ""

        set_node_name(n2, proc_name, type_name)

        if proc_name == "setup":
          found_setup = true
      else:
        discard

  if not found_setup:
    template setup_proc(self, typeName, setup_proc)=
      method setup(self: typeName)
      method setup_proc(self: typeName)

    template setup_decl(self, base_method)=
      method setup()=
        self.base_method()
        discard

    var setup_proc_typename = ident("setup" & $typeName.toStrLit())
    var base_method_name = ident("setup" & $baseName.toStrLit())
    result.add(getAst(setup_proc(ident(obj_reference), typeName, setup_proc_typename)))
    body.add(getAst(setup_decl(ident(obj_reference), base_method_name))[0])

  # Iterate over the statements, adding `self: T`
  # to the parameters of functions
  for node in body.children:
    case node.kind:
      of nnkMethodDef, nnkProcDef:
        # inject `self: T` into the arguments
        let n = copyNimTree(node)
        n.params.insert(1, newIdentDefs(ident(obj_reference), typeName))

        # Copy the proc or method for inheritance
        # ie: procName_ClassName()
        let n2 = copyNimTree(node)
        n2.params.insert(1, newIdentDefs(ident(obj_reference), typeName))

        let type_name = $(typeName.toStrLit())
        var proc_name = $(n2.name.toStrLit())
        var is_assignment = proc_name.contains("=")

        set_node_name(n2, proc_name, type_name)

        if proc_name == "setup":
          let dot_name = newDotExpr(ident(obj_reference), ident("name"))
          let set_name = newAssignment(dot_name, newLit(typeName))
          n2.body.add(set_name)
        else:
          let proc_call = newDotExpr(ident(obj_reference),
                                     ident(proc_name & type_name))

          template set_test_name(self, proc_name)=
            self.current_test_name = proc_name

          template try_block(self, test_call)=
            self.num_tests += 1
            try:
              test_call
              styled_echo(styleBright, fgGreen, "[OK]",
                          fgWhite, "     ", self.current_test_name)
              self.tests_passed += 1
            except TestAssertError:
              let e = (ref TestAssertError)(getCurrentException())
              styled_echo(styleBright,
                          fgRed, "[Failed]",
                          fgWhite, " ", self.current_test_name, e.msg)

          run_tests[0][6].add(getAst(set_test_name(ident(obj_reference), proc_name)))
          run_tests[0][6].add(getAst(try_block(ident(obj_reference), proc_call)))

        # simply call the class method from here
        # proc procName=
        #    procName_ClassName()
        var p: seq[NimNode] = @[]
        for i in 1..n.params.len-1:
          p.add(n.params[i][0])
        if is_assignment:
          let dot = newDotExpr(ident(obj_reference), ident(proc_name & type_name))
          n.body = newStmtList(newAssignment(dot, p[1]))
        else:
          n.body = newStmtList(newCall(proc_name & type_name, p))

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

  var type_decl: NimNode

  template declare_type_export(tname, bname)=
    type tname* = ref object of bname
  template declare_type(tname, bname)=
    type tname = ref object of bname

  if baseName == nil:
    if export_class:
      type_decl = getAst(declare_type_export(typeName, TestSuite))
    else:
      type_decl = getAst(declare_type(typeName, TestSuite))
  else:
    if export_class:
      type_decl = getAst(declare_type_export(typeName, baseName))
    else:
      type_decl = getAst(declare_type(typeName, baseName))

  # Inspect the tree structure:
  #
  # echo type_decl.treeRepr
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
  type_decl[0][0][2][0][2] = recList

  # insert the type declaration
  result.insert(0, type_decl)

  # insert libs needed
  result.insert(0, getAst(import_required_libs()))
  
  result.add(run_tests)

  template add_test_suite(typeName)=
    test_suites.add(typeName())

  result.add(getAst(add_test_suite(typeName)))

proc run_tests*()=
  for suite in test_suites:
    suite.setup()

    styled_echo(styleBright,
                fgYellow, "\n[Running]",
                fgWhite, " $1\n".format(suite.name))
    suite.run_tests()

    # Output red if tests didn't pass, green otherwise
    var color = fgGreen
    if suite.tests_passed != suite.num_tests:
      color = fgRed

    styled_echo(styleBright, color,
                "\n[", $suite.tests_passed, "/", $suite.num_tests, "]",
                fgWhite, " tests passed.\n")

