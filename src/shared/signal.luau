--!strict
export type Listener = (...any) -> ()

export type Signal = {
    connect: (Signal, Listener) -> () -> (),
    fire: (Signal, ...any) -> (),
    clear: (Signal) -> (),
}

local signal = {}

function signal.new(): Signal
    local listeners: { Listener } = {}

    local self = {
        connect = function(_: Signal, fn: Listener): () -> ()
            table.insert(listeners, fn)
            return function()
                for i = #listeners, 1, -1 do
                    if listeners[i] == fn then
                        table.remove(listeners, i)
                    end
                end
            end
        end,
        fire = function(_: Signal, ...: any)
            for _, fn in listeners do
                task.spawn(fn, ...)
            end
        end,
        clear = function(_: Signal)
            table.clear(listeners)
        end,
    } :: Signal

    return self
end

return signal
