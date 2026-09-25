local T = require("testlib")
local test, eq, truthy, falsy = T.test, T.eq, T.truthy, T.falsy

-- The APL modules are pure Lua, so one loaded addon serves every test.
local s = T.newAddon()
local APL = s.ns.APL
local Lexer, Compiler = APL.Lexer, APL.Compiler

-- A resolver over a fixed table of values; unknown names are errors.
local function Resolver(values, calls)
    return function(name)
        if values[name] == nil then return nil, "unknown name '" .. name .. "'" end
        return function()
            if calls then calls[name] = (calls[name] or 0) + 1 end
            return values[name]
        end
    end
end

local function Eval(text, values)
    local fn, message, col = Compiler.CompileExpression(text, Resolver(values or {}))
    if not fn then error(("compile failed: %s (col %s)"):format(message, tostring(col)), 2) end
    return fn({})
end

local function CompileError(text, values)
    local fn, message, col = Compiler.CompileExpression(text, Resolver(values or {}))
    if fn then error("expected a compile error for '" .. text .. "'", 2) end
    return message, col
end

---------------------------------------------------------------------------
-- Lexer
---------------------------------------------------------------------------
test("lexer: identifiers, operators and numbers with positions", function()
    local tokens = Lexer.Tokenize("buff.killing_machine.up&runic_power>=100")
    local got = {}
    for _, t in ipairs(tokens) do got[#got + 1] = t.type .. ":" .. tostring(t.value) .. "@" .. t.pos end
    eq(table.concat(got, " "), "ident:buff.killing_machine.up@1 op:&@24 ident:runic_power@25 op:>=@36 num:100@38 eof:nil@41", "tokens")
end)

test("lexer: && || == are aliases", function()
    local tokens = Lexer.Tokenize("a&&b||c==d")
    eq(tokens[2].value .. tokens[4].value .. tokens[6].value, "&|=", "aliases")
end)

test("lexer: numbers", function()
    eq(Lexer.Tokenize("1.5")[1].value, 1.5, "decimal")
    eq(Lexer.Tokenize(".5")[1].value, 0.5, "leading dot")
    local _, message, pos = Lexer.Tokenize("1+1.")
    eq(message .. "@" .. pos, "invalid number '1.'@3", "trailing dot")
    _, message = Lexer.Tokenize("1.2.3")
    eq(message, "invalid number '1.2.3'", "two dots")
    _, message = Lexer.Tokenize("1e5")
    eq(message, "invalid number '1e5'", "exponent")
end)

test("lexer: path parts may start with a digit", function()
    local tokens = Lexer.Tokenize("trinket.1.cooldown.remains")
    eq(tokens[1].value, "trinket.1.cooldown.remains", "single identifier")
end)

test("lexer: errors", function()
    local _, message, pos = Lexer.Tokenize("a+$b")
    eq(message .. "@" .. pos, "unexpected character '$'@3", "bad character")
    _, message, pos = Lexer.Tokenize("buff.")
    eq(message .. "@" .. pos, "identifier can't end with '.'@5", "trailing dot")
end)

---------------------------------------------------------------------------
-- Expressions
---------------------------------------------------------------------------
test("arithmetic and precedence", function()
    eq(Eval("1+2*3"), 7, "* before +")
    eq(Eval("(1+2)*3"), 9, "parentheses")
    eq(Eval("10%4"), 2.5, "% divides")
    eq(Eval("10%%4"), 2, "%% is modulo")
    eq(Eval("5%0"), 0, "division by zero")
    eq(Eval("5%%0"), 0, "modulo by zero")
    eq(Eval("-3+5"), 2, "unary minus")
    eq(Eval("@-3"), 3, "abs")
    eq(Eval("2-1-1"), 0, "left associative -")
    eq(Eval("8%2%2"), 2, "left associative %")
    eq(Eval("--2"), 2, "double negation")
end)

test("logic returns 1 or 0", function()
    eq(Eval("1&0"), 0, "and")
    eq(Eval("2&3"), 1, "and of non-zero")
    eq(Eval("1|0"), 1, "or")
    eq(Eval("0|0"), 0, "or false")
    eq(Eval("!0"), 1, "not 0")
    eq(Eval("!5"), 0, "not 5")
    eq(Eval("1^1"), 0, "xor same")
    eq(Eval("1^0"), 1, "xor different")
end)

test("comparisons", function()
    eq(Eval("3>=3"), 1, ">=")
    eq(Eval("3=3"), 1, "=")
    eq(Eval("3==3"), 1, "==")
    eq(Eval("3!=3"), 0, "!=")
    eq(Eval("2<3"), 1, "<")
    eq(Eval("3<=2"), 0, "<=")
    eq(Eval("3>2"), 1, ">")
end)

test("& binds tighter than |, comparisons tighter than &", function()
    eq(Eval("1|0&0"), 1, "1|(0&0)")
    eq(Eval("1<2&3>4"), 0, "(1<2)&(3>4)")
    eq(Eval("1+1=2"), 1, "(1+1)=2")
    eq(Eval("!0&0"), 0, "(!0)&0")
end)

test("names resolve to values, booleans as numbers", function()
    local v = { ["buff.a.up"] = 1, ["buff.b.up"] = 1, runic_power = 85, ["runic_power.deficit"] = 45 }
    eq(Eval("buff.a.up+buff.b.up>=2", v), 1, "counting booleans")
    eq(Eval("runic_power>=80&runic_power.deficit<50", v), 1, "mixed")
    eq(Eval("runic_power%10", v), 8.5, "division of a name")
end)

test("&, | short-circuit", function()
    local calls = {}
    local fn = Compiler.CompileExpression("zero&x|one|y", Resolver({ zero = 0, one = 1, x = 1, y = 1 }, calls))
    eq(fn({}), 1, "result")
    eq(calls.x, nil, "x not evaluated after 0&")
    eq(calls.y, nil, "y not evaluated after 1|")
end)

test("a name used twice is resolved once", function()
    local resolved = 0
    local fn, _, _, count = Compiler.CompileExpression("a+a*a", function(name)
        resolved = resolved + 1
        return function() return 2 end
    end)
    eq(fn({}), 6, "value")
    eq(resolved, 1, "resolver calls")
    eq(count, 1, "getter count")
end)

test("getters receive the state", function()
    local fn = Compiler.CompileExpression("hp<35", function()
        return function(state) return state.hp end
    end)
    eq(fn({ hp = 20 }), 1, "low")
    eq(fn({ hp = 90 }), 0, "high")
end)

test("expression errors report the column", function()
    local message, col = CompileError("1+")
    eq(message .. "@" .. col, "expected a value but found end of expression@3", "dangling operator")
    message, col = CompileError("(1+2")
    eq(message .. "@" .. col, "expected ')' but found end of expression@5", "unclosed paren")
    message, col = CompileError("1 2")
    eq(message .. "@" .. col, "unexpected '2'@3", "missing operator")
    message, col = CompileError("")
    eq(message .. "@" .. col, "empty expression@1", "empty")
    message, col = CompileError("1+foo.bar")
    eq(message .. "@" .. col, "unknown name 'foo.bar'@3", "unknown name")
    message, col = CompileError("1+)")
    eq(message .. "@" .. col, "expected a value but found ')'@3", "stray paren")
end)

---------------------------------------------------------------------------
-- Action lists
---------------------------------------------------------------------------
-- Accepts any dotted name as 0 unless given in `values`.
local function Permissive(values)
    values = values or {}
    return function(name)
        return function() return values[name] or 0 end
    end
end

local ABILITIES = { obliterate = true, frost_strike = true, howling_blast = true, icy_touch = true,
    plague_strike = true, horn_of_winter = true, death_and_decay = true, blood_strike = true }

local function Compile(text, values)
    return Compiler.CompileAPL(text, {
        resolve = Permissive(values),
        isAction = function(name) return ABILITIES[name] end,
    })
end

local function Errors(apl)
    local out = {}
    for _, err in ipairs(apl.errors) do out[#out + 1] = Compiler.FormatError(err) end
    return table.concat(out, "\n")
end

local function Names(list)
    local out = {}
    for _, action in ipairs(list) do out[#out + 1] = action.name end
    return table.concat(out, ",")
end

local SAMPLE = [[
# Frost DK sample
actions.precombat=horn_of_winter,if=!buff.horn_of_winter.up

actions=call_action_list,name=aoe,if=active_enemies>=3
actions+=/icy_touch,if=dot.frost_fever.remains<gcd
actions+=/obliterate,if=runes.frost>=1&runes.unholy>=1
actions+=/frost_strike,if=runic_power.deficit<20|buff.killing_machine.up
actions+=/howling_blast/horn_of_winter

actions.aoe=howling_blast
actions.aoe+=/death_and_decay,line_cd=5
]]

test("parses lists, appends and multi-action lines", function()
    local apl = Compile(SAMPLE)
    eq(Errors(apl), "", "errors")
    eq(table.concat(apl.listOrder, ","), "precombat,default,aoe", "list order")
    eq(Names(apl.lists.default), "call_action_list,icy_touch,obliterate,frost_strike,howling_blast,horn_of_winter", "default")
    eq(Names(apl.lists.aoe), "howling_blast,death_and_decay", "aoe")
    eq(apl.lists.aoe[2].lineCd, 5, "line_cd")
    eq(apl.lists.default[1].kind, "call", "call kind")
    eq(apl.lists.default[1].target, "aoe", "call target")
    eq(apl.lists.default[2].kind, "ability", "ability kind")
    eq(apl.lists.default[2].line, 5, "line number")
end)

test("compiled conditions evaluate", function()
    local apl = Compile(SAMPLE, { ["runes.frost"] = 1, ["runes.unholy"] = 0, ["buff.killing_machine.up"] = 1 })
    local list = apl.lists.default
    eq(list[3].condition({}), 0, "obliterate needs an unholy rune")
    eq(list[4].condition({}), 1, "frost strike with KM")
    falsy(list[5].condition, "no condition")
end)

test("'=' replaces a list", function()
    local apl = Compile("actions=obliterate\nactions+=/frost_strike\nactions=icy_touch")
    eq(Names(apl.lists.default), "icy_touch", "replaced")
end)

test("syntax errors keep the rest of the APL", function()
    local apl = Compile(table.concat({
        "actions=obliterate",
        "action+=/frost_strike",              -- 2: typo in 'actions'
        "actions.=icy_touch",                 -- 3: empty list name
        "actions+=/frost_strike,iff=1",       -- 4: unknown option
        "actions+=/frost_strike,if",          -- 5: missing =
        "actions+=/frost_strike,if=1,if=2",   -- 6: duplicate
        "actions+=/,if=1",                    -- 7: missing action name
        "actions+=/howling_blast",
    }, "\n"))
    eq(Errors(apl), table.concat({
        "line 2, col 1: expected 'actions=', 'actions+=/' or 'actions.NAME='",
        "line 3, col 8: invalid list name '.'",
        "line 4, col 24: unknown option 'iff'",
        "line 5, col 24: expected key=value but found 'if'",
        "line 6, col 29: duplicate option 'if'",
        "line 7, col 11: missing action name",
    }, "\n"), "errors")
    eq(Names(apl.lists.default), "obliterate,howling_blast", "good lines kept")
end)

test("condition errors point at the column in the line", function()
    local apl = Compile("actions=obliterate,if=runes.frost>=1&(")
    eq(Errors(apl), "line 1, col 39: if: expected a value but found end of expression", "column")
    eq(#apl.lists.default, 0, "bad action dropped")
end)

test("indented lines and comments", function()
    local apl = Compile("  # comment\n  actions=obliterate,if=1+\n")
    eq(Errors(apl), "line 2, col 27: if: expected a value but found end of expression", "column with indent")
end)

test("semantic errors", function()
    local apl = Compile(table.concat({
        "actions=call_action_list,name=missing",
        "actions+=/run_action_list",
        "actions+=/obliterat",
        "actions+=/wait",
        "actions+=/obliterate,line_cd=soon",
        "actions+=/variable,name=x,op=bogus,value=1",
        "actions+=/frost_strike,if=variable.nope>1",
    }, "\n"))
    eq(Errors(apl), table.concat({
        "line 1, col 31: no action list named 'missing'",
        "line 2, col 11: run_action_list needs name=",
        "line 3, col 11: unknown action 'obliterat'",
        "line 4, col 11: wait needs sec=",
        "line 5, col 30: line_cd must be a number of seconds",
        "line 6, col 30: unknown variable op 'bogus'",
        "line 7, col 27: if: unknown variable 'nope'",
    }, "\n"), "errors")
end)

test("a missing default list is an error", function()
    local apl = Compile("actions.aoe=howling_blast")
    eq(Errors(apl), "no default list ('actions=...')", "error")
end)

test("variables compile and read state.variables", function()
    local apl = Compile(table.concat({
        "actions=variable,name=pool,value=runic_power<40",
        "actions+=/variable,name=km,op=setif,condition=buff.killing_machine.up,value=1,value_else=0",
        "actions+=/variable,name=pool,op=reset",
        "actions+=/frost_strike,if=!variable.pool&variable.km",
    }, "\n"), { runic_power = 30 })
    eq(Errors(apl), "", "errors")
    local list = apl.lists.default
    eq(list[1].kind .. "/" .. list[1].op .. "/" .. list[1].variable, "variable/set/pool", "set")
    eq(list[1].value({}), 1, "value")
    eq(list[2].op, "setif", "setif op")
    truthy(list[2].varCondition and list[2].value and list[2].valueElse, "setif parts")
    eq(list[3].op, "reset", "reset needs no value")
    eq(list[4].condition({ variables = { pool = 0, km = 1 } }), 1, "reads variables")
    eq(list[4].condition({ variables = {} }), 0, "unset variables are 0")
end)

test("setif requires condition, value and value_else", function()
    local apl = Compile("actions=variable,name=x,op=setif,value=1")
    eq(Errors(apl), "line 1, col 9: variable needs condition=\nline 1, col 9: variable needs value_else=", "errors")
end)

test("SimC boilerplate actions are ignored, not errors", function()
    local apl = Compile("actions=auto_attack\nactions+=/snapshot_stats\nactions+=/obliterate")
    eq(Errors(apl), "", "errors")
    eq(apl.lists.default[1].kind, "ignored", "auto_attack")
    eq(apl.lists.default[3].kind, "ability", "obliterate")
end)

test("wait compiles its duration", function()
    local apl = Compile("actions=wait,sec=cooldown.x.remains,if=cooldown.x.remains<1", { ["cooldown.x.remains"] = 0.4 })
    local action = apl.lists.default[1]
    eq(action.kind, "wait", "kind")
    eq(action.sec({}), 0.4, "sec")
end)

test("Windows line endings are fine", function()
    local apl = Compile("actions=obliterate\r\nactions+=/frost_strike,if=1+\r\n")
    eq(Errors(apl), "line 2, col 29: if: expected a value but found end of expression", "column ignores \\r")
end)
