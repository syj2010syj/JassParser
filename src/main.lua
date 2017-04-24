(function()
	local exepath = package.cpath:sub(1, (package.cpath:find(';') or (#package.cpath+1))-6)
	package.path = package.path .. ';' .. exepath .. '..\\?.lua'
end)()

require 'filesystem'
require 'utility'
local uni  = require 'unicode'
local parser = require 'parser'

local function load_in_env(name, env)
    local path = package.searchpath(name, package.path)
    return assert(load(io.load(fs.path(path)), path, 't', setmetatable(env, { __index = _G })))()
end

local function main()
    if not arg[1] then
        local test = require 'test'
        return
    end
    local jass = io.load(fs.path(uni.a2u(arg[1])))
    local t = parser(jass)
    print(t)
end

main()
