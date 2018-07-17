local ast = require 'parser.ast'
local writer = require 'writer'

local function checkeq (x, y, p)
    if x == IGNORE or y == IGNORE then
        return x and y
    end
    if p then
        print(x, y)
    end
    if type(x) == "table" and type(y) == 'table' then
        for k, v in pairs(x) do 
            if not checkeq(v, y[k], p) then
                return false
            end
        end
        for k, v in pairs(y) do
            if not checkeq(v, x[k], p) then
                return false
            end
        end
        return true
    else
        return x == y
    end
end

local function test(name)
    local function check(str)
        return function(tbl)
            if name ~= 'Jass' then
                str = str:gsub('[\r\n]+$', '')
            end
            local res, comments = ast(str, 'war3map.j', name)
            if type(res) ~= 'table' then
                local lines = {}
                lines[#lines+1] = '没能匹配成语法树'
                lines[#lines+1] = '=========jass========'
                lines[#lines+1] = str
                error(table.concat(lines, '\n'))
            end
            if not checkeq(res, tbl) then
                local lines = {}
                lines[#lines+1] = '语法测试未通过'
                lines[#lines+1] = '=========jass========'
                lines[#lines+1] = str
                lines[#lines+1] = '========语法树======='
                lines[#lines+1] = writer(res)
                lines[#lines+1] = '=========期望========'
                lines[#lines+1] = writer(tbl)
                error(table.concat(lines, '\n'))
            end
            return function (tbl)
                if not checkeq(comments, tbl) then
                    local lines = {}
                    lines[#lines+1] = '注释测试未通过'
                    lines[#lines+1] = '=========jass========'
                    lines[#lines+1] = str
                    lines[#lines+1] = '=========注释======='
                    lines[#lines+1] = writer(comments)
                    lines[#lines+1] = '=========期望========'
                    lines[#lines+1] = writer(tbl)
                    error(table.concat(lines, '\n'))
                end
            end
        end
    end

    local filename = 'test.ast.' .. name
    local env = setmetatable({ check = check }, _G)
    assert(loadfile(package.searchpath(filename, package.path), 'bt', env))()
end

test 'Value'
test 'Exp'
test 'Type'
test 'Globals'
test 'Local'
test 'Action'
test 'Native'
test 'Function'
test 'Jass'