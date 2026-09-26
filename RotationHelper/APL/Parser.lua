local ADDON_NAME, ns = ...

-- Parses SimC-style action priority lists.
--
--   ## comments start with '#'
--   actions.precombat=horn_of_winter
--   actions=call_action_list,name=aoe,if=active_enemies>=3
--   actions+=/obliterate,if=runes.frost>=1&runes.unholy>=1
--   actions.aoe=howling_blast/death_and_decay
--
-- `actions=` targets the "default" list, `actions.NAME=` a named one.
-- `=` replaces the list, `+=` appends; several actions can be given at once
-- separated by '/'. Expressions follow SimC: '%' is division ('/' separates
-- actions), '%%' is modulo, and every value is a number (true = 1).
ns.APL = ns.APL or {}
local Parser = {}
ns.APL.Parser = Parser

local Lexer = ns.APL.Lexer

---------------------------------------------------------------------------
-- Expressions
---------------------------------------------------------------------------
-- Binary operators by precedence; higher binds tighter. All left-associative.
local BINARY_PRECEDENCE = {
    ["|"] = 1, ["^"] = 1,
    ["&"] = 2,
    ["="] = 3, ["!="] = 3, ["<"] = 3, ["<="] = 3, [">"] = 3, [">="] = 3,
    ["+"] = 4, ["-"] = 4,
    ["*"] = 5, ["%"] = 5, ["%%"] = 5,
}
local UNARY = { ["!"] = true, ["-"] = true, ["@"] = true }

local function Fail(message, pos)
    error({ message = message, pos = pos }, 0)
end

local function Describe(token)
    if token.type == "eof" then return "end of expression" end
    return "'" .. tostring(token.value) .. "'"
end

-- AST nodes:
--   { type = "num", value }       { type = "var", name }
--   { type = "unop", op, expr }   { type = "binop", op, left, right }
-- Every node also has `pos`, its column in the expression.
local function ParseTokens(tokens)
    local i = 1
    local ParseBinary

    local function ParseUnary()
        local t = tokens[i]
        if t.type == "op" and UNARY[t.value] then
            i = i + 1
            return { type = "unop", op = t.value, expr = ParseUnary(), pos = t.pos }
        elseif t.type == "num" then
            i = i + 1
            return { type = "num", value = t.value, pos = t.pos }
        elseif t.type == "ident" then
            i = i + 1
            return { type = "var", name = t.value, pos = t.pos }
        elseif t.type == "op" and t.value == "(" then
            i = i + 1
            local expr = ParseBinary(1)
            if tokens[i].type ~= "op" or tokens[i].value ~= ")" then
                Fail("expected ')' but found " .. Describe(tokens[i]), tokens[i].pos)
            end
            i = i + 1
            return expr
        end
        Fail("expected a value but found " .. Describe(t), t.pos)
    end

    function ParseBinary(minPrecedence)
        local left = ParseUnary()
        while true do
            local t = tokens[i]
            local precedence = t.type == "op" and BINARY_PRECEDENCE[t.value]
            if not precedence or precedence < minPrecedence then break end
            i = i + 1
            local right = ParseBinary(precedence + 1)
            left = { type = "binop", op = t.value, left = left, right = right, pos = t.pos }
        end
        return left
    end

    if tokens[1].type == "eof" then Fail("empty expression", 1) end
    local ast = ParseBinary(1)
    if tokens[i].type ~= "eof" then
        Fail("unexpected " .. Describe(tokens[i]), tokens[i].pos)
    end
    return ast
end

-- Returns the AST, or nil, message, column.
function Parser.ParseExpression(text)
    local tokens, message, pos = Lexer.Tokenize(text)
    if not tokens then return nil, message, pos end
    local ok, result = pcall(ParseTokens, tokens)
    if ok then return result end
    if type(result) == "table" then return nil, result.message, result.pos end
    error(result, 0)
end

---------------------------------------------------------------------------
-- Action lists
---------------------------------------------------------------------------
-- Options an action line may carry.
Parser.KNOWN_OPTIONS = {
    ["if"] = true,       -- condition
    name = true,         -- list name (call/run_action_list) or variable name
    value = true,        -- variable value
    value_else = true,   -- variable value when condition is false (op=setif)
    condition = true,    -- variable condition (op=setif)
    op = true,           -- variable operation
    sec = true,          -- wait duration
    line_cd = true,      -- minimum seconds between uses of this line
    slot = true,         -- use_item: 13 or 14 (trinket1 / trinket2)
}

-- Splits `text` on `sep`, returning pieces with their start offsets.
local function Split(text, sep, offset)
    local pieces = {}
    local start = 1
    while true do
        local s = text:find(sep, start, true)
        local piece = text:sub(start, (s or 0) - 1)
        pieces[#pieces + 1] = { text = piece, col = offset + start - 1 }
        if not s then break end
        start = s + 1
    end
    return pieces
end

-- Parses "name,key=value,key=value" at column `col` of line `lineNo`.
local function ParseAction(piece, listName, lineNo, errors)
    local parts = Split(piece.text, ",", piece.col)
    local name = parts[1].text
    local action = {
        name = name, list = listName, line = lineNo, col = piece.col, text = piece.text,
        params = {}, paramCols = {},
    }
    if not name:find("^[%a_][%w_]*$") then
        errors[#errors + 1] = { line = lineNo, col = piece.col,
            message = name == "" and "missing action name" or ("invalid action name '" .. name .. "'") }
        return nil
    end
    for i = 2, #parts do
        local part = parts[i]
        local key, value = part.text:match("^([%w_]+)=(.*)$")
        if not key then
            errors[#errors + 1] = { line = lineNo, col = part.col,
                message = "expected key=value but found '" .. part.text .. "'" }
            return nil
        elseif not Parser.KNOWN_OPTIONS[key] then
            errors[#errors + 1] = { line = lineNo, col = part.col, message = "unknown option '" .. key .. "'" }
            return nil
        elseif action.params[key] then
            errors[#errors + 1] = { line = lineNo, col = part.col, message = "duplicate option '" .. key .. "'" }
            return nil
        end
        action.params[key] = value
        action.paramCols[key] = part.col + #key + 1
    end
    return action
end

-- Returns { lists = { name = { action, ... } }, listOrder = { ... }, errors = { ... } }.
-- Each error is { line, col, message }. Lines with errors are left out.
function Parser.ParseAPL(text)
    local apl = { lists = {}, listOrder = {}, errors = {} }
    local errors = apl.errors
    local lineNo = 0

    for rawLine in (text .. "\n"):gmatch("([^\n]*)\n") do
        lineNo = lineNo + 1
        local line = rawLine:gsub("%s+$", "")
        local lead = #line:match("^%s*")
        local body = line:sub(lead + 1)

        if body ~= "" and body:sub(1, 1) ~= "#" then
            local suffix, assign, rest = body:match("^actions([%w_%.]*)(%+?=)(.*)$")
            local listName = suffix and (suffix == "" and "default" or suffix:match("^%.([%w_]+)$"))
            if not suffix then
                errors[#errors + 1] = { line = lineNo, col = lead + 1,
                    message = "expected 'actions=', 'actions+=/' or 'actions.NAME='" }
            elseif not listName then
                errors[#errors + 1] = { line = lineNo, col = lead + 8, message = "invalid list name '" .. suffix .. "'" }
            else
                local restCol = lead + #"actions" + #suffix + #assign + 1
                if rest:sub(1, 1) == "/" then
                    rest = rest:sub(2)
                    restCol = restCol + 1
                end

                local list = apl.lists[listName]
                if not list then
                    list = {}
                    apl.lists[listName] = list
                    apl.listOrder[#apl.listOrder + 1] = listName
                elseif assign == "=" then
                    for k in pairs(list) do list[k] = nil end
                end

                for _, piece in ipairs(Split(rest, "/", restCol)) do
                    local action = ParseAction(piece, listName, lineNo, errors)
                    if action then list[#list + 1] = action end
                end
            end
        end
    end
    return apl
end
