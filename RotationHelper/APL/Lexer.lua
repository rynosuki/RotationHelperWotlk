local ADDON_NAME, ns = ...

-- Splits a SimC-style condition expression into tokens.
--
--   buff.killing_machine.up&runic_power>=100
--   -> ident "buff.killing_machine.up", op "&", ident "runic_power", op ">=", num 100
--
-- Each token is { type = "num"|"ident"|"op"|"eof", value = ..., pos = column }.
ns.APL = ns.APL or {}
local Lexer = {}
ns.APL.Lexer = Lexer

local find, sub, tonumber = string.find, string.sub, tonumber

-- Longest first, so ">=" wins over ">". "&&", "||" and "==" are accepted
-- as aliases for SimC's "&", "|" and "=".
local OPERATORS = {
    "&&", "||", "==", "!=", "<=", ">=", "%%",
    "&", "|", "^", "!", "=", "<", ">", "+", "-", "*", "%", "@", "(", ")",
}
local ALIASES = { ["&&"] = "&", ["||"] = "|", ["=="] = "=" }

-- Returns the token list, or nil, message, column.
function Lexer.Tokenize(text)
    local tokens = {}
    local pos, len = 1, #text
    while pos <= len do
        local c = sub(text, pos, pos)
        if find(c, "^%s") then
            pos = pos + 1
        elseif find(c, "^[%d%.]") then
            local s, e = find(text, "^%d*%.?%d+", pos)
            if not s then
                return nil, "invalid number", pos
            end
            -- "1." isn't a valid number, and "1.2.3" shouldn't lex as "1.2" ".3"
            if find(text, "^[%.%w_]", e + 1) then
                return nil, "invalid number '" .. (text:match("^[%w_%.]+", pos)) .. "'", pos
            end
            tokens[#tokens + 1] = { type = "num", value = tonumber(sub(text, s, e)), pos = pos }
            pos = e + 1
        elseif find(c, "^[%a_]") then
            -- Identifiers are dotted paths; parts after the first may start
            -- with a digit (e.g. trinket.1.cooldown.remains).
            local s, e = find(text, "^[%a_][%w_]*", pos)
            while true do
                local s2, e2 = find(text, "^%.[%w_]+", e + 1)
                if not s2 then break end
                e = e2
            end
            if sub(text, e + 1, e + 1) == "." then
                return nil, "identifier can't end with '.'", e + 1
            end
            tokens[#tokens + 1] = { type = "ident", value = sub(text, s, e), pos = pos }
            pos = e + 1
        else
            local matched
            for _, op in ipairs(OPERATORS) do
                if sub(text, pos, pos + #op - 1) == op then
                    matched = op
                    break
                end
            end
            if not matched then
                return nil, "unexpected character '" .. c .. "'", pos
            end
            tokens[#tokens + 1] = { type = "op", value = ALIASES[matched] or matched, pos = pos }
            pos = pos + #matched
        end
    end
    tokens[#tokens + 1] = { type = "eof", pos = len + 1 }
    return tokens
end
