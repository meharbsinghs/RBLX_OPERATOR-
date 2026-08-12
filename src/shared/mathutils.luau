--!strict
local mathutils = {}

function mathutils.clamp01(value: number): number
    return math.clamp(value, 0, 1)
end

function mathutils.lerp(a: number, b: number, t: number): number
    return a + (b - a) * t
end

-- Framerate-independent exponential damping toward a target.
function mathutils.damp(current: number, target: number, lambda: number, dt: number): number
    return mathutils.lerp(current, target, 1 - math.exp(-lambda * dt))
end

-- Random direction inside a cone around `forward` (angle in radians).
function mathutils.coneDirection(forward: Vector3, angle: number): Vector3
    if angle <= 0 then
        return forward.Unit
    end
    local right = forward:Cross(Vector3.new(0, 1, 0))
    if right.Magnitude < 0.01 then
        right = Vector3.new(1, 0, 0)
    end
    right = right.Unit
    local up = right:Cross(forward).Unit
    local a = math.random() * math.pi * 2
    local r = math.sqrt(math.random()) * math.tan(angle)
    return (forward + (right * math.cos(a) + up * math.sin(a)) * r).Unit
end

function mathutils.distanceXZ(a: Vector3, b: Vector3): number
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

function mathutils.round(value: number): number
    return math.floor(value + 0.5)
end

function mathutils.shuffle<T>(list: { T }): { T }
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

function mathutils.formatNumber(value: number): string
    local abs = math.abs(value)
    local suffix = ""
    if abs >= 1000000 then
        suffix = "M"
        value = value / 1000000
    elseif abs >= 1000 then
        suffix = "K"
        value = value / 1000
    end
    return string.format("%.0f%s", value, suffix)
end

return mathutils
