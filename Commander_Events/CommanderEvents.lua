callbacks = {}

function AddListener(event, func)
    if not event then return end
    if not callbacks[event] then
        callbacks[event] = {}
    end
    table.insert(callbacks[event], func)
end

function Notify(event)
    if event and callbacks[event] then
        for _, func in ipairs(callbacks[event]) do
            func()
        end
    end
end