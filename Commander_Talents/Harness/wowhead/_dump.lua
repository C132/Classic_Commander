
local file, token = ...
CommanderTalentsData = { Classes = {} }
function CommanderTalentsData.AddPvPBuilds() end
assert(loadfile(file))()
local class = CommanderTalentsData.Classes[token]
assert(class, "missing class " .. tostring(token))
for _, tree in ipairs(class.trees) do
    for _, t in ipairs(tree.talents) do
        for i = 1, #t.ranks do
            print(table.concat({ tree.bg, tree.name, t.name, t.icon,
                t.row, t.col, t.max, i, (t.ranks[i]:gsub("\n", "\\n")) }, "\t"))
        end
    end
end
