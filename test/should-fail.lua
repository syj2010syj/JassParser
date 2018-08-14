-- 外部单元测试
local parser = require 'parser'
local format_error = require 'parser.format_error'
local check_path = fs.path(root) / 'test' / 'should-fail'

local function check_result(str, name, err, warn, lua, errors)
    if #errors == 0 then
        local lines = {}
        lines[#lines+1] = name .. ':未捕获错误'
        lines[#lines+1] = '=========期望========'
        lines[#lines+1] = err or warn
        lines[#lines+1] = '=========jass========'
        lines[#lines+1] = str
        error(table.concat(lines, '\n'))
    end
    if err then
        local ok, anyErr
        for _, error in ipairs(errors) do
            if err == error.err then
                ok = error
                break
            end
            if 'error' == error.level then
                anyErr = error
            end
        end
        if not ok then
            local lines = {}
            lines[#lines+1] = name .. ':错误不正确'
            lines[#lines+1] = '=========期望========'
            lines[#lines+1] = err
            lines[#lines+1] = '=========实际========'
            lines[#lines+1] = format_error(anyErr)
            lines[#lines+1] = '=========jass========'
            lines[#lines+1] = str
            error(table.concat(lines, '\n'))
        end
        if ok.level ~= 'error' then
            local lines = {}
            lines[#lines+1] = name .. ':错误等级不正确'
            lines[#lines+1] = '=========期望========'
            lines[#lines+1] = 'error'
            lines[#lines+1] = '=========实际========'
            lines[#lines+1] = ok.level
            error(table.concat(lines, '\n'))
        end
    end
    if warn then
        local ok
        for _, error in ipairs(errors) do
            if 'error' == error.level then
                ok = error
                break
            end
        end
        if ok then
            local lines = {}
            lines[#lines+1] = name .. ':错误等级不正确'
            lines[#lines+1] = '=========期望========'
            lines[#lines+1] = '[warning]'
            lines[#lines+1] = warn
            lines[#lines+1] = '=========实际========'
            lines[#lines+1] = '[error]'
            lines[#lines+1] = format_error(ok)
            error(table.concat(lines, '\n'))
        end
        local ok
        for _, error in ipairs(errors) do
            if warn == error.err then
                ok = error
                break
            end
        end
        if not ok then
            local lines = {}
            lines[#lines+1] = name .. ':警告不正确'
            lines[#lines+1] = '=========期望========'
            lines[#lines+1] = warn
            lines[#lines+1] = '=========实际========'
            lines[#lines+1] = format_error(errors[1])
            lines[#lines+1] = '=========jass========'
            lines[#lines+1] = str
            error(table.concat(lines, '\n'))
        end
    end
    if lua then
        local ok, err = lua(errors)
        if not ok then
            local lines = {}
            lines[#lines+1] = name .. ':错误检查失败'
            lines[#lines+1] = '=========jass========'
            lines[#lines+1] = str
            lines[#lines+1] = '=========原因========'
            lines[#lines+1] = err
            error(table.concat(lines, '\n'))
        end
    end
end

local function check_str(str, name, err, warn, lua)
    if not err and not warn and not lua then
        return
    end
    local ast, comments, errors, gram = parser.parser(str, name)
    check_result(str, name, err, warn, lua, errors)
    local errors = parser.checker(str, name)
    check_result(str, name, err, warn, lua, errors)
    return true
end

local ok = 0
local skips = {}
for path in check_path:list_directory() do
    if path:extension():string() == '.j' then
        local file_name = path:filename():string()
        local str = io.load(path)
        local err = io.load(path:parent_path() / (path:stem():string() .. '.err'))
        local warn = io.load(path:parent_path() / (path:stem():string() .. '.warn'))
        local lua = io.load(path:parent_path() / (path:stem():string() .. '.lua'))
        if lua then
            lua = load(lua, '@'..(path:parent_path() / (path:stem():string() .. '.lua')):string())
        end
        local suc = check_str(str, file_name, err, warn, lua)
        if suc then
            ok = ok + 1
        else
            skips[#skips+1] = path:stem():string()
        end
    end
end
print(('共检查[%d]个错误，跳过[%d]个错误'):format(ok, #skips))
for _, skip in ipairs(skips) do
    print('', skip)
end