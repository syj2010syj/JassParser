local exepath
(function()
	exepath = package.cpath:sub(1, package.cpath:find(';')-6)
	package.path = package.path .. ';' .. exepath .. '..\\?.lua'
	package.path = package.path .. ';' .. exepath .. '..\\?\\init.lua'
end)()

require 'filesystem'
require 'utility'
local uni  = require 'unicode'
local convert_lua = require 'convert_lua'
local parser = require 'parser'
local writer = require 'writer'

local function load_in_env(name, env)
    local path = package.searchpath(name, package.path)
    return assert(load(io.load(fs.path(path)), path, 't', setmetatable(env, { __index = _G })))()
end

local function main()
    if not arg[1] then
        require 'test'
        return
    end
    local root = fs.path(uni.a2u(exepath)):parent_path():parent_path():parent_path()
    print(root)
    local t = {}
    local lua = {}
    for i = 1, 4 do
        if arg[i] then
            local jass = io.load(fs.path(uni.a2u(arg[i])))
            lua[i], t[i] = convert_lua(jass)
        end
    end
    local jass, cj, bj, as = t[1], t[2], t[3], t[4]
    local buf = writer(jass)
    io.save(root / '语法树.lua', buf)
    io.save(root / '转换.lua', lua[1])
    print('完成')
end

main()
