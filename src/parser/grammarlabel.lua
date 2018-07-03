local re = require 'parser.relabel'
local m = require 'lpeglabel'
local lang = require 'lang'

local scriptBuf = ''
local compiled = {}
local defs = {}
local comments

defs.nl = m.P'\r\n' + m.S'\r\n'
defs.s  = m.S' \t' + m.P'\xEF\xBB\xBF'
defs.S  = - defs.s
function defs.True()
    return true
end
function defs.False()
    return false
end
function defs.Integer10(neg, str)
    local int = math.tointeger(str)
    if neg == '' then
        return int
    else
        return - int
    end
end
function defs.Integer16(neg, str)
    local int = math.tointeger('0x'..str)
    if neg == '' then
        return int
    else
        return - int
    end
end
function defs.Integer256(neg, str)
    local int
    if #str == 1 then
        int = str:byte()
    elseif #str == 4 then
        int = ('>I4'):unpack(str)
    end
    if neg == '' then
        return int
    else
        return - int
    end
end

local eof = re.compile '!. / %{SYNTAX_ERROR}'

local function grammar(tag)
    return function (script)
        scriptBuf = script .. '\r\n' .. scriptBuf
        compiled[tag] = re.compile(scriptBuf, defs) * eof
    end
end

grammar 'Comment' [[
Comment     <-  '//' [^%nl]*
]]

grammar 'Sp' [[
Sp          <-  (%s / Comment)*
]]

grammar 'Nl' [[
Nl          <-  (Sp %nl)+
]]

grammar 'Common' [[
RESERVED    <-  GLOBALS / ENDGLOBALS / CONSTANT / NATIVE / ARRAY / AND / OR / NOT / TYPE / EXTENDS / FUNCTION / ENDFUNCTION / NOTHING / TAKES / RETURNS / CALL / SET / RETURN / IF / ENDIF / ELSEIF / ELSE / LOOP / ENDLOOP / EXITWHEN -- TODO 先匹配名字再通过表的key来排除预设值可以提升性能？
Cut         <-  ![a-zA-Z0-9_]
COMMA       <-  Sp ','
ASSIGN      <-  Sp '=' !'='
GLOBALS     <-  Sp 'globals' Cut
ENDGLOBALS  <-  Sp 'endglobals' Cut
CONSTANT    <-  Sp 'constant' Cut
NATIVE      <-  Sp 'native' Cut
ARRAY       <-  Sp 'array' Cut
AND         <-  Sp 'and' Cut
OR          <-  Sp 'or' Cut
NOT         <-  Sp 'not' Cut
TYPE        <-  Sp 'type' Cut
EXTENDS     <-  Sp 'extends' Cut
FUNCTION    <-  Sp 'function' Cut
ENDFUNCTION <-  Sp 'endfunction' Cut
NOTHING     <-  Sp 'nothing' Cut
TAKES       <-  Sp 'takes' Cut
RETURNS     <-  Sp 'returns' Cut
CALL        <-  Sp 'call' Cut
SET         <-  Sp 'set' Cut
RETURN      <-  Sp 'return' Cut
IF          <-  Sp 'if' Cut
THEN        <-  Sp 'then' Cut
ENDIF       <-  Sp 'endif' Cut
ELSEIF      <-  Sp 'elseif' Cut
ELSE        <-  Sp 'else' Cut
LOOP        <-  Sp 'loop' Cut
ENDLOOP     <-  Sp 'endloop' Cut
EXITWHEN    <-  Sp 'exitwhen' Cut
LOCAL       <-  Sp 'local' Cut
TRUE        <-  Sp 'true' Cut
FALSE       <-  Sp 'false' Cut
]]

grammar 'Value' [[
Value       <-  {| NULL / Boolean / String / Real / Integer |}
NULL        <-  Sp 'null' Cut
                {:type: '' -> 'null':}

Boolean     <-  {:value: TRUE -> True / FALSE -> False :}
                {:type: '' -> 'boolean':}

StringC     <-  Sp '"' {(SEsc / [^"])*} '"'
SEsc        <-  '\' .
String      <-  {:value: StringC :}
                {:type: '' -> 'string':}

RealC       <-  Sp {'-'? Sp (('.' [0-9]+) / ([0-9]+ '.' [0-9]*))}
Real        <-  {:value: RealC :}
                {:type: '' -> 'real':}

Integer10   <-  Sp ({'-'?} Sp {'0' / ([1-9] [0-9]*)})
            ->  Integer10
Integer16   <-  Sp ({'-'?} Sp ('$' / '0x' / '0X') {[a-fA-F0-9]+})
            ->  Integer16
Integer256  <-  Sp ({'-'?} Sp "'" {('\\' / "\'" / (!"'" .))*} "'")
            ->  Integer256
Integer     <-  {:value: Integer16 / Integer10 / Integer256 :}
                {:type: '' -> 'integer':}
]]

grammar 'Name' [[
Name        <-  !RESERVED Sp [a-zA-Z] [a-zA-Z0-9_]*
]]

grammar 'Word' [[
Word        <-  Value / Name
]]

grammar 'Compare' [[
Compare     <-  UE / EQ / LE / LT / GE / GT
GT          <-  Sp '>'
GE          <-  Sp '>='
LT          <-  Sp '<'
LE          <-  Sp '<='
EQ          <-  Sp '=='
UE          <-  Sp '!='
]]

grammar 'Operator' [[
ADD         <-  Sp '+'
SUB         <-  Sp '-'
MUL         <-  Sp '*'
DIV         <-  Sp '/'
NEG         <-  Sp '-'
]]

grammar 'Paren' [[
PL          <-  Sp '('
PR          <-  Sp ')'
BL          <-  Sp '['
BR          <-  Sp ']'
]]

grammar 'Exp' [[
Exp         <-  EAnd
EAnd        <-  EOr      (AND         EOr)*
EOr         <-  ECompare (OR          ECompare)*
ECompare    <-  ENot     (Compare     ENot)*
ENot        <-            NOT*        EAdd
EAdd        <-  EMul     ((ADD / SUB) EMul)*
EMul        <-  EUnit    ((MUL / DIV) EUnit)*
EUnit       <-  EParen / ECode / ECall / EValue / ENeg

EParen      <-  PL Exp PR

ECode       <-  FUNCTION ECodeFunc
ECodeFunc   <-  Name

ECall       <-  ECallFunc PL ECallArgs? PR -- TODO 先匹配右括号可以提升性能？
ECallFunc   <-  Name
ECallArgs   <-  ECallArg (COMMA ECallArg)*
ECallArg    <-  Exp

EValue      <-  EVari / EVar / EWord
EVari       <-  EVar BL EIndex BR
EIndex      <-  Exp
EVar        <-  Name
EWord       <-  Word

ENeg        <-  NEG EUnit
]]

grammar 'Type' [[
Type        <-  TYPE TChild EXTENDS TParent
TChild      <-  Name
TParent     <-  Name
]]

grammar 'Globals' [[
Globals     <-  GLOBALS Nl
                    Global*
                GEnd
Global      <-  (GConstant? GType GArray? GName GExp?)? Nl
GConstant   <-  CONSTANT
GType       <-  Name
GArray      <-  ARRAY
GName       <-  Name
GExp        <-  ASSIGN Exp
GEnd        <-  ENDGLOBALS
]]

grammar 'Local' [[
Local       <-  LOCAL LType LArray? LName LExp?
Locals      <-  (Local? Nl)*

LType       <-  Name
LArray      <-  ARRAY
LName       <-  Name
LExp        <-  ASSIGN Exp
]]

grammar 'Action' [[
Action      <-  ACall / ASet / ASeti / AReturn / AExit / ALogic / ALoop
Actions     <-  (Action? Nl)*

ACall       <-  CALL ACallFunc PL ACallArgs? PR -- TODO 先匹配右括号可以提升性能？
ACallFunc   <-  Name
ACallArgs   <-  Exp (COMMA ACallArg)*
ACallArg    <-  Exp

ASet        <-  SET ASetName ASSIGN ASetValue
ASetName    <-  Name
ASetValue   <-  Exp

ASeti       <-  SET ASetiName BL ASetiIndex BR ASSIGN ASetiValue
ASetiName   <-  Name
ASetiIndex  <-  Exp
ASetiValue  <-  Exp

AReturn     <-  RETURN AReturnExp?
AReturnExp  <-  Exp

AExit       <-  EXITWHEN AExitExp
AExitExp    <-  Exp

ALogic      <-  LIf
                LElseif*
                LElse?
                LEnd
LIf         <-  IF     Exp THEN Nl Actions
LElseif     <-  ELSEIF Exp THEN Nl Actions
LElse       <-  ELSE            Nl Actions
LEnd        <-  ENDIF

ALoop       <-  LOOP Nl Actions LoopEnd
LoopEnd     <-  ENDLOOP
]]

grammar 'Native' [[
Native      <-  NConstant? NATIVE NName NTakes NReturns
NConstant   <-  CONSTANT
NName       <-  Name
NTakes      <-  TAKES (NTNothing / NArgs)
NTNothing   <-  NOTHING
NArgs       <-  NArg (COMMA NArg)*
NArg        <-  NArgType NArgName
NArgType    <-  Name
NArgName    <-  Name
NReturns    <-  RETURNS (NRNothing / NRExp)
NRNothing   <-  NOTHING
NRExp       <-  Exp
]]

grammar 'Function' [[
Function    <-  FConstant? FUNCTION FName FTakes FReturns
                    FLocals
                    FActions
                FEnd
FConstant   <-  CONSTANT
FName       <-  Name
FTakes      <-  TAKES (FTNothing / FArgs)
FTNothing   <-  NOTHING
FArgs       <-  FArg (COMMA FArg)*
FArg        <-  FArgType FArgName
FArgType    <-  Name
FArgName    <-  Name
FReturns    <-  RETURNS (FRNothing / FRExp) Nl
FRNothing   <-  NOTHING
FRExp       <-  Exp
FLocals     <-  Locals
FActions    <-  Actions
FEnd        <-  ENDFUNCTION
]]

grammar 'Jass' [[
Jass        <-  Nl? Chunk (Nl Chunk)* Nl? Sp
Chunk       <-  Type / Globals / Native / Function
]]

local mt = {}
setmetatable(mt, mt)

local function errorpos(jass, file, pos, err)
    local line, col = re.calcline(jass, pos)
    local sp = col - 1
    local start  = jass:find('[^\r\n]', pos-sp) or pos
    local finish = jass:find('[\r\n]', pos+1)
    if finish then
        finish = finish - 1
    else
        finish = #jass
    end
    local text = ('%s\r\n%s^'):format(jass:sub(start, finish), (' '):rep(sp))
    error(lang.parser.ERROR_POS:format(err, file, line, text))
end

function mt:__call(jass, file, mode)
    comments = {}
    local r, e, pos = compiled[mode]:match(jass)
    if not r then
        errorpos(jass, file, pos, lang.PARSER[e])
    end

    return r, comments
end

return mt
