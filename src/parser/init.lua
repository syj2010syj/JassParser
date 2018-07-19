local parser = require 'parser.parser'

local api = {}

function api.parser(jass, file, option)
    if not option then
        option = {}
    end
    if not option.mode then
        option.mode = 'Jass'
    end
    return parser(jass, file, option)
end

function api.war3map(...)
    local ast, comments
    local option = { mode = 'Jass' }
    for i, jass in ipairs {...} do
        local file
        if i == 1 then
            file = 'common.j'
        elseif i == 2 then
            file = 'blizzard.j'
        else
            file = 'war3map.j'
        end
        ast, comments = parser(jass, file, option)
    end
    return ast, comments
end

return api
