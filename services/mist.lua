local shader = require("tew.Vapourmist.components.shader")

local MIN_DISTANCE = 8192 * 1.5
local MAX_DISTANCE = 8192 * 3
local MAX_DEPTH = 8192 / 12
local WtC = tes3.worldController.weatherController

local fogId = "tew_mist"

local mist = {}

---@type mwseTimer
local FOG_TIMER

---@type fogParams
local fogParams = {
    color = tes3vector3.new(),
    center = tes3vector3.new(),
    radius = tes3vector3.new(MAX_DISTANCE, MAX_DISTANCE, MAX_DEPTH),
    density = 15,
}

local function getCloudColourMix(fogComp, skyComp)
	return math.lerp(fogComp, skyComp, 0.1)
end

local function getDarkerColour(comp)
	return math.clamp(math.lerp(comp, 0.0, 0.1), 0.03, 0.88)
end

-- Calculate output colours from current fog colour --
local function getOutputValues()
	local currentFogColor = WtC.currentFogColor:copy()
	local currentSkyColor = WtC.currentSkyColor:copy()
	local weatherColour = {
		r = getCloudColourMix(currentFogColor.r, currentSkyColor.r),
		g = getCloudColourMix(currentFogColor.g, currentSkyColor.g),
		b = getCloudColourMix(currentFogColor.b, currentSkyColor.b)
	}

	return tes3vector3.new(
        getDarkerColour(weatherColour.r),
        getDarkerColour(weatherColour.g),
        getDarkerColour(weatherColour.b)
    )
end

local function updateDensity(dist)
    local f = math.clamp(dist, MIN_DISTANCE, MAX_DISTANCE)
    f = math.remap(f, MIN_DISTANCE, MAX_DISTANCE, 15.0, 0.0)

    local cell = tes3.getPlayerCell()
    local x = cell.gridX
    local y = cell.gridY

    local mistCenter = tes3vector3.new(
        (x + 0.5) * 8192,
        (y + 0.5) * 8192,
        0
    )

    fogParams.density = f
    fogParams.center = mistCenter
    fogParams.color = getOutputValues()

    shader.createOrUpdateFog(fogId, fogParams)
end

local function update(e)
    if tes3.player.cell.isInterior then
        return
    end

	local currDist = 0
    local prevDist = e.timer.data.prevDist or currDist

    if math.min(currDist, prevDist) <= MAX_DISTANCE then
        updateDensity(currDist)
    end

    e.timer.data.prevDist = currDist
end
event.register(tes3.event.loaded, function()
    FOG_TIMER = timer.start({
        iterations = -1,
        duration = 1 / 10,
        callback = update,
        data = {},
    })
end)

--- @param e cellChangedEventData
function mist.onCellChanged(e)
    local dist = 5000
    if dist > MAX_DISTANCE or e.cell.isInterior then
        shader.deleteFog(fogId)
        FOG_TIMER:pause()
    else
        shader.createOrUpdateFog(fogId, fogParams)
        FOG_TIMER:resume()
    end
end

return mist
