local ADDON_NAME, ns = ...

-- Compiles parsed expressions and action lists into Lua functions.
--
-- Names like `buff.killing_machine.up` are bound at compile time through a
-- resolver: resolve(name) returns a getter `function(state) -> number`, or
-- nil plus an error message. So typos are caught when the APL loads, and
-- evaluating a condition does no name lookups at all.
--
-- A compiled condition is `function(state) -> number`; non-zero means true.
ns.APL = ns.APL or {}
local Compiler = {}
ns.APL.Compiler = Compiler

local Parser = ns.APL.Parser
local format, concat, loadstring, setfenv, unpack = string.format, table.concat, loadstring, setfenv, unpack
local abs, fmod = math.abs, math.fmod

-- Division and modulo by zero return 0, as in SimC.
local function Div(a, b) if b == 0 then return 0 end return a / b end
local function Mod(a, b) if b == 0 then return 0 end return fmod(a, b) end

local COMPARE = { ["="] = "==", ["!="] = "~=", ["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=" }
local ARITHMETIC = { ["+"] = "+", ["-"] = "-", ["*"] = "*" }

local EMPTY_ENV = setmetatable({}, { __newindex = function() error("APL code can't set globals", 2) end })

local function Fail(message, pos)
    error({ message = message, pos = pos }, 0)
end

-- Turns an AST into a Lua expression string. `getters` collects one getter
-- per distinct name; the generated code calls them as g1(s), g2(s), ...
local function Emit(node, resolve, getters, getterIndex)
    local t = node.type
    if t == "num" then
        return format("%.17g", node.value)
    elseif t == "var" then
        local index = getterIndex[node.name]
        if not index then
            local getter, message = resolve(node.name)
            if not getter then Fail(message or ("unknown name '" .. node.name .. "'"), node.pos) end
            getters[#getters + 1] = getter
            index = #getters
            getterIndex[node.name] = index
        end
        return "g" .. index .. "(s)"
    elseif t == "unop" then
        local x = Emit(node.expr, resolve, getters, getterIndex)
        if node.op == "!" then return "(" .. x .. "==0 and 1 or 0)" end
        if node.op == "-" then return "(-" .. x .. ")" end
        return "abs(" .. x .. ")" -- '@'
    end

    local x = Emit(node.left, resolve, getters, getterIndex)
    local y = Emit(node.right, resolve, getters, getterIndex)
    local op = node.op
    if op == "&" then
        return "(" .. x .. "~=0 and " .. y .. "~=0 and 1 or 0)"
    elseif op == "|" then
        return "((" .. x .. "~=0 or " .. y .. "~=0) and 1 or 0)"
    elseif op == "^" then
        return "(((" .. x .. "~=0)~=(" .. y .. "~=0)) and 1 or 0)"
    elseif COMPARE[op] then
        return "(" .. x .. COMPARE[op] .. y .. " and 1 or 0)"
    elseif ARITHMETIC[op] then
        return "(" .. x .. ARITHMETIC[op] .. y .. ")"
    elseif op == "%" then
        return "div(" .. x .. "," .. y .. ")"
    elseif op == "%%" then
        return "mod(" .. x .. "," .. y .. ")"
    end
    Fail("unsupported operator '" .. op .. "'", node.pos)
end

-- Compiles one expression. Returns fn, or nil, message, column.
function Compiler.CompileExpression(text, resolve)
    local ast, message, pos = Parser.ParseExpression(text)
    if not ast then return nil, message, pos end

    local getters, getterIndex = {}, {}
    local ok, result = pcall(Emit, ast, resolve, getters, getterIndex)
    if not ok then
        if type(result) == "table" then return nil, result.message, result.pos end
        error(result, 0)
    end

    local names = { "div", "mod", "abs" }
    for i = 1, #getters do names[#names + 1] = "g" .. i end
    local code = "local " .. concat(names, ",") .. " = ...\nreturn function(s) return " .. result .. " end"
    local chunk, loadError = loadstring(code, "=APL expression")
    if not chunk then
        -- Only possible if Emit produced bad Lua, i.e. a bug here.
        return nil, "internal compiler error: " .. tostring(loadError), 1
    end
    setfenv(chunk, EMPTY_ENV)
    return chunk(Div, Mod, abs, unpack(getters)), nil, nil, #getters
end

---------------------------------------------------------------------------
-- Action lists
---------------------------------------------------------------------------
local LIST_ACTIONS = { call_action_list = true, run_action_list = true }

-- SimC boilerplate that has no meaning here; kept in the list but skipped.
Compiler.IGNORED_ACTIONS = {
    auto_attack = true, snapshot_stats = true, flask = true, food = true,
    augmentation = true, use_items = true,
}

-- SimC's use_item,slot=N as our trinket abilities.
local ITEM_SLOTS = { ["13"] = "trinket1", ["14"] = "trinket2" }

local VARIABLE_OPS = { set = true, add = true, sub = true, mul = true, div = true,
    min = true, max = true, reset = true, setif = true }

-- Compiles the expression in `action.params[key]`, recording errors.
local function CompileParam(action, key, resolve, errors)
    local text = action.params[key]
    local fn, message, pos = Compiler.CompileExpression(text, resolve)
    if not fn then
        errors[#errors + 1] = { line = action.line, col = action.paramCols[key] + (pos or 1) - 1,
            message = format("%s: %s", key, message) }
    end
    return fn
end

local function Require(action, key, errors)
    if action.params[key] and action.params[key] ~= "" then return true end
    errors[#errors + 1] = { line = action.line, col = action.col,
        message = format("%s needs %s=", action.name, key) }
    return false
end

-- Compiles one action in place. Returns false if it has errors.
local function CompileAction(action, apl, resolve, isAction, errors)
    local before = #errors
    local p = action.params
    if action.name == "use_item" then
        local key = ITEM_SLOTS[p.slot or ""]
        if not key then
            errors[#errors + 1] = { line = action.line, col = action.col,
                message = "use_item needs slot=13 or slot=14 (or write trinket1 / trinket2)" }
            return false
        end
        action.name = key
    end
    local name = action.name

    if p["if"] then action.condition = CompileParam(action, "if", resolve, errors) end
    if p.line_cd then
        action.lineCd = tonumber(p.line_cd)
        if not action.lineCd or action.lineCd < 0 then
            errors[#errors + 1] = { line = action.line, col = action.paramCols.line_cd,
                message = "line_cd must be a number of seconds" }
        end
    end

    if LIST_ACTIONS[name] then
        if Require(action, "name", errors) and not apl.lists[p.name] then
            errors[#errors + 1] = { line = action.line, col = action.paramCols.name,
                message = "no action list named '" .. p.name .. "'" }
        end
        action.kind = name == "call_action_list" and "call" or "run"
        action.target = p.name
    elseif name == "variable" then
        action.kind = "variable"
        action.op = p.op or "set"
        if not VARIABLE_OPS[action.op] then
            errors[#errors + 1] = { line = action.line, col = action.paramCols.op,
                message = "unknown variable op '" .. action.op .. "'" }
        end
        if Require(action, "name", errors) then action.variable = p.name end
        if action.op == "setif" then
            if Require(action, "condition", errors) then
                action.varCondition = CompileParam(action, "condition", resolve, errors)
            end
            if Require(action, "value", errors) then action.value = CompileParam(action, "value", resolve, errors) end
            if Require(action, "value_else", errors) then
                action.valueElse = CompileParam(action, "value_else", resolve, errors)
            end
        elseif action.op ~= "reset" then
            if Require(action, "value", errors) then action.value = CompileParam(action, "value", resolve, errors) end
        end
    elseif name == "wait" then
        action.kind = "wait"
        if Require(action, "sec", errors) then action.sec = CompileParam(action, "sec", resolve, errors) end
    elseif Compiler.IGNORED_ACTIONS[name] then
        action.kind = "ignored"
    else
        action.kind = "ability"
        if isAction and not isAction(name) then
            errors[#errors + 1] = { line = action.line, col = action.col, message = "unknown action '" .. name .. "'" }
        end
    end

    return #errors == before
end

-- Parses and compiles an APL. Options:
--   resolve(name)  -> getter or nil, message   (required)
--   isAction(name) -> true if `name` is a usable ability
-- `variable.NAME` is resolved here: it reads state.variables[NAME].
-- Returns the APL (see Parser.ParseAPL); actions with errors are removed,
-- and apl.errors lists every problem sorted by line and column.
function Compiler.CompileAPL(text, opts)
    local apl = Parser.ParseAPL(text)
    local errors = apl.errors

    -- Variables can be read anywhere, so collect their names first.
    local variables = {}
    for _, list in pairs(apl.lists) do
        for _, action in ipairs(list) do
            if action.name == "variable" and action.params.name then
                variables[action.params.name] = true
            end
        end
    end
    apl.variables = variables

    local function resolve(name)
        local varName = name:match("^variable%.([%w_]+)$")
        if varName then
            if not variables[varName] then return nil, "unknown variable '" .. varName .. "'" end
            return function(s) return s.variables[varName] or 0 end
        end
        return opts.resolve(name)
    end

    for _, listName in ipairs(apl.listOrder) do
        local list = apl.lists[listName]
        local kept = {}
        for _, action in ipairs(list) do
            if CompileAction(action, apl, resolve, opts.isAction, errors) then
                kept[#kept + 1] = action
            end
        end
        apl.lists[listName] = kept
    end

    if not apl.lists.default then
        errors[#errors + 1] = { line = 0, col = 0, message = "no default list ('actions=...')" }
    end

    table.sort(errors, function(a, b)
        if a.line ~= b.line then return a.line < b.line end
        return a.col < b.col
    end)
    return apl
end

-- "line 7, col 23: expected ')' but found end of expression"
function Compiler.FormatError(err)
    if err.line == 0 then return err.message end
    return format("line %d, col %d: %s", err.line, err.col, err.message)
end
