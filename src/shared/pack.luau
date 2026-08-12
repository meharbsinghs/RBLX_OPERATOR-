--!strict
-- ============================================================================
--  Payload compression helpers.
--
--  Roblox serializes every string KEY in a remote payload as a full string.
--  Hot channels (enemy state batches, scoreboards, kill feeds) get much
--  cheaper over the wire when keys are small integers. makeEncoder() hands
--  out a stable int <-> string map for the lifetime of a session, so both
--  sides can compress and decompress without any extra round-trips.
-- ============================================================================

local pack = {}

export type Encoder = {
    encode: (value: string) -> number,
    decode: (id: number) -> string?,
    clear: () -> (),
}

function pack.makeEncoder(): Encoder
    local byString: { [string]: number } = {}
    local byId: { [number]: string } = {}
    local next = 1
    return {
        encode = function(value: string): number
            local existing = byString[value]
            if existing then
                return existing
            end
            byString[value] = next
            byId[next] = value
            next += 1
            return next - 1
        end,
        decode = function(id: number): string?
            return byId[id]
        end,
        clear = function()
            byString = {}
            byId = {}
            next = 1
        end,
    }
end

return pack
