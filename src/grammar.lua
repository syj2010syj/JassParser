local lpeg = require 'lpeg'

local tonumber = tonumber
local table_concat = table.concat

lpeg.locale(lpeg)

local S = lpeg.S
local P = lpeg.P
local R = lpeg.R
local C = lpeg.C
local V = lpeg.V
local Cg = lpeg.Cg
local Ct = lpeg.Ct
local Cc = lpeg.Cc
local Cs = lpeg.Cs
local Cp = lpeg.Cp
local Cmt = lpeg.Cmt

local jass
local line_count = 1
local line_pos = 1

local function errorpos(pos, str)
    local endpos = jass:find('[\r\n]', pos) or (#jass+1)
    local sp = (' '):rep(pos-line_pos)
    local line = ('%s|\r\n%s\r\n%s|'):format(sp, jass:sub(line_pos, endpos-1), sp)
    error(('第[%d]行: %s:\n===========================\n%s\n==========================='):format(line_count, str, line))
end

local function err(str)
    return Cp() / function(pos)
        errorpos(pos, str)
    end
end

local function newline(pos)
    line_count = line_count + 1
    line_pos = pos
end

local w = (1-S' \t\r\n()[]')^0

local function expect(p, ...)
    if select('#', ...) == 1 then
        local str = ...
        return p + w * err(str)
    else
        local m, str = ...
        return p + m * err(str)
    end
end

local function keyvalue(key, value)
    return Cg(Cc(value), key)
end

local function currentline()
    return Cg(P(true) / function() return line_count end, 'line')
end

local function binary(...)
    local e1, op = ...
    if not op then
        return e1
    end
    local args = {...}
    local e1 = args[1]
    for i = 2, #args, 2 do
        op, e2 = args[i], args[i+1]
        e1 = {
            type = op,
            [1] = e1,
            [2] = e2,
        }
    end
    return e1
end

local nl  = (P'\r\n' + S'\r\n') * Cp() / newline
local com = P'//' * (1-nl)^0
local sp  = (S' \t' + P'\xEF\xBB\xBF' + com)^0
local sps = (S' \t' + P'\xEF\xBB\xBF' + com)^1
local cl  = com^0 * nl
local spl = sp * cl

local Keys = {'globals', 'endglobals', 'constant', 'native', 'array', 'and', 'or', 'not', 'type', 'extends', 'function', 'endfunction', 'nothing', 'takes', 'returns', 'call', 'set', 'return', 'if', 'endif', 'elseif', 'else', 'loop', 'endloop', 'exitwhen'}
for _, key in ipairs(Keys) do
    Keys[key] = true
end

local Id = P{
    'Def',
    Def  = C(V'Id') * Cp() / function(id, pos) if Keys[id] then errorpos(pos-#id, ('不能使用关键字[%s]作为函数名或变量名'):format(id)) end end,
    Id   = R('az', 'AZ') * R('az', 'AZ', '09', '__')^0,
}

local Null = Ct(keyvalue('type', 'null') * P'null')

local Bool = P{
    'Def',
    Def   = Ct(keyvalue('type', 'boolean') * Cg(V'True' + V'False', 'value')),
    True  = P'true' * Cc(true),
    False = P'false' * Cc(false),
}

local Str = P{
    'Def',
    Def  = Ct(keyvalue('type', 'string') * Cg(V'Str', 'value')),
    Str  = '"' * Cs((nl + V'Char')^0) * '"',
    Char = V'Esc' + '\\' * err'不合法的转义字符' + (1-P'"'),
    Esc  = P'\\b' / function() return '\b' end 
         + P'\\t' / function() return '\t' end
         + P'\\r' / function() return '\r' end
         + P'\\n' / function() return '\n' end
         + P'\\f' / function() return '\f' end
         + P'\\"' / function() return '\"' end
         + P'\\\\' / function() return '\\' end,
}

local Real = P{
    'Def',
    Def  = Ct(keyvalue('type', 'real') * Cg(V'Real', 'value')),
    Real = V'Neg' * V'Char' / function(neg, n) return neg and -n or n end,
    Neg   = Cc(true) * P'-' * sp + Cc(false),
    Char  = (P'.' * expect(R'09'^1, '不合法的实数') + R'09'^1 * P'.' * R'09'^0) / tonumber,
}

local Int = P{
    'Def',
    Def    = Ct(keyvalue('type', 'integer') * Cg(V'Int', 'value')),
    Int    = V'Neg' * (V'Int16' + V'Int10' + V'Int256') / function(neg, n) return neg and -n or n end,
    Neg    = Cc(true) * P'-' * sp + Cc(false),
    Int10  = (P'0' + R'19' * R'09'^0) / tonumber,
    Int16  = (P'$' + P'0' * S'xX') * expect(R('af', 'AF', '09')^1 / function(n) return tonumber('0x'..n) end, '不合法的16进制整数'),
    Int256 = "'" * expect((V'C4' + V'C1') * "'", '256进制整数必须是由1个或者4个字符组成'),
    C4     = V'C4W' * V'C4W' * V'C4W' * V'C4W' / function(n) return ('>I4'):unpack(n) end,
    C4W    = expect(1-P"'"-P'\\', '\\' * P(1), '4个字符组成的256进制整数不能使用转义字符'),
    C1     = ('\\' * expect(V'Esc', P(1), '不合法的转义字符') + C(1-P"'")) / function(n) return ('I1'):unpack(n) end,
    Esc    = P'b' / function() return '\b' end 
           + P't' / function() return '\t' end
           + P'r' / function() return '\r' end
           + P'n' / function() return '\n' end
           + P'f' / function() return '\f' end
           + P'"' / function() return '\"' end
           + P'\\' / function() return '\\' end,
}

local Value = sp * (Null + Bool + Str + Real + Int) * sp

local Exp = P{
    'Def',
    
    -- 由低优先级向高优先级递归
    Def      = V'Or',
    Exp      = V'Paren' + V'Func' + V'Call' + Value + V'Vari' + V'Var' + V'Neg',

    -- 由于不消耗字符串,只允许向下递归
    Or       = V'And'     * (C'or'                     * V'And')^0     / binary,
    And      = V'Compare' * (C'and'                    * V'Compare')^0 / binary,
    Compare  = V'AddSub'  * (C(S'><=!' * P'=' + S'><') * V'AddSub')^0  / binary,
    AddSub   = V'MulDiv'  * (C(S'+-')                  * V'MulDiv')^0  / binary,
    MulDiv   = V'Not'     * (C(S'*/')                  * V'Not')^0     / binary,

    -- 由于消耗了字符串,可以递归回顶层
    Not   = Ct(keyvalue('type', 'not') * sp * 'not' * (V'Not' + V'Exp')) + sp * V'Exp',

    -- 由于消耗了字符串,可以递归回顶层
    Paren = Ct(keyvalue('type', 'paren')    * sp * '(' * Cg(V'Def', 1) * ')' * sp),
    Func  = Ct(keyvalue('type', 'function') * sp * 'function' * sps * Cg(Id, 'name') * sp),
    Call  = Ct(keyvalue('type', 'call')     * sp * Cg(Id, 'name') * '(' * V'Args' * ')' * sp),
    Vari  = Ct(keyvalue('type', 'vari')     * sp * Cg(Id, 'name') * sp * '[' * Cg(V'Def', 1) * ']' * sp),
    Var   = Ct(keyvalue('type', 'var')      * sp * Cg(Id, 'name') * sp),
    Neg   = Ct(keyvalue('type', 'neg')      * sp * '-' * sp * Cg(V'Exp', 1)),

    Args  = V'Def' * (',' * V'Def')^0 + sp,
}

local Type = P{
    'Def',
    Def  = Ct(sp * 'type' * keyvalue('type', 'type') * currentline() * expect(sps * Cg(Id, 'name'), '变量类型定义错误') * expect(V'Ext', '类型继承错误')),
    Ext  = sps * 'extends' * sps * Cg(Id, 'extends'),
}

local Global = P{
    'Global',
    Global = Ct(sp * 'globals' * keyvalue('type', 'globals') * currentline() * V'Vals' * V'End'),
    Vals   = (spl + V'Def' * spl)^0,
    Def    = Ct(currentline() * sp
        * ('constant' * sps * keyvalue('constant', true) + P(true))
        * Cg(Id, 'type') * sps
        * ('array' * sps * keyvalue('array', true) + P(true))
        * Cg(Id, 'name')
        * (sp * '=' * Cg(Exp) + P(true))
        ),
    End    = expect(sp * P'endglobals', '缺少endglobals'),
}

local Local = P{
    'Def',
    Def = Ct(currentline() * sp
        * 'local' * sps
        * Cg(Id, 'type') * sps
        * ('array' * sps * keyvalue('array', true) + P(true))
        * Cg(Id, 'name')
        * (sp * '=' * Cg(Exp) + P(true))
        ),
}

local Line = P{
    'Def',
    Def    = sp * (V'Call' + V'Set' + V'Seti' + V'Return' + V'Exit'),
    Call   = Ct(keyvalue('type', 'call') * currentline() * 'call' * sps * Cg(Id, 'name') * sp * '(' * V'Args' * ')' * sp),
    Args   = Exp * (',' * Exp)^0 + sp,
    Set    = Ct(keyvalue('type', 'set') * currentline() * 'set' * sps * Cg(Id, 'name') * sp * '=' * Exp),
    Seti   = Ct(keyvalue('type', 'seti') * currentline() * 'set' * sps * Cg(Id, 'name') * sp * '[' * Cg(Exp, 1) * ']' * sp * '=' * Cg(Exp, 2)),
    Return = Ct(keyvalue('type', 'return') * currentline() * 'return' * (Cg(Exp, 1) + P(true))),
    Exit   = Ct(keyvalue('type', 'exit') * currentline() * 'exitwhen' * sps * Cg(Exp, 1)),
}

local Logic = P{
    'Def',
    Def      = V'If' + V'Loop',

    If       = Ct(keyvalue('type', 'if') * currentline() * sp
            * V'Ifif'
            * V'Ifelseif'^0 
            * V'Ifelse'^-1
            * sp * 'endif'
            ),
    Ifif     = Ct(keyvalue('type', 'if') * currentline() * sp * 'if' * #(1-Id) * Cg(Exp, 'condition') * 'then' * spl * V'Ifdo'),
    Ifelseif = Ct(keyvalue('type', 'elseif') * currentline() * sp * 'elseif' * #(1-Id) * Cg(Exp, 'condition') * 'then' * spl * V'Ifdo'),
    Ifelse   = Ct(keyvalue('type', 'else') * currentline() * sp * 'else' * spl * V'Ifdo'),
    Ifdo     = (spl + V'Def' + Line * spl)^0,

    Loop     = Ct(keyvalue('type', 'loop') * currentline() * sp
            * 'loop' * spl
            * (spl + V'Def' + Line * spl)^0
            * sp * 'endloop'
            ),
}

local Function = P{
    'Def',
    Def      = Ct(keyvalue('type', 'function') * (V'Common' + V'Native')),
    Native   = sp * (P'constant' * keyvalue('constant', true) + P(true)) * sp * 'native' * keyvalue('native', true) * V'Head',
    Common   = sp * 'function' * V'Head' * V'Content' * V'End',
    Head     = sps * Cg(Id, 'name') * sps * 'takes' * sps * V'Takes' * sps * 'returns' * sps * V'Returns' * spl,
    Takes    = ('nothing' + Cg(V'Args', 'args')),
    Args     = Ct(sp * V'Arg' * (sp * ',' * sp * V'Arg')^0),
    Arg      = Ct(Cg(Id, 'type') * sps * Cg(Id, 'name')),
    Returns  = 'nothing' + Cg(Id, 'returns'),
    Content  = sp * Cg(V'Locals', 'locals') * V'Lines',
    Locals   = Ct((spl + Local * spl)^0),
    Lines    = (spl + Logic * spl + Line * spl)^0,
    End    = expect(sp * P'endfunction', '缺少endfunction'),
}

local pjass = expect(sps + cl + Type + Function + Global, P(1), '语法不正确')^0

local mt = {}
setmetatable(mt, mt)

mt.Value  = Value
mt.Id     = Id
mt.Exp    = Exp
mt.Global = Global
mt.Local  = Local
mt.Line   = Line
mt.Logic  = Logic
mt.Function = Function

function mt:__call(_jass, mode)
    jass = _jass
    line_count = 1
    line_pos = 1
    lpeg.setmaxstack(1000)
    
    if mode then
        return Ct((mt[mode] + spl)^1 + err'语法不正确'):match(_jass)
    else
        return Ct(pjass):match(_jass)
    end
end

return mt
