-- Clouds module
-->>>---------------------------------------------------------------------------------------------<<<--

-- Imports
local clouds = {}
local util = require("tew.Vapourmist.components.util")
local debugLog = util.debugLog
local config = require("tew.Vapourmist.config")

-->>>---------------------------------------------------------------------------------------------<<<--
-- Constants

local CELL_SIZE = 8192
local MIN_SPEED = 15
local TIMER_DURATION = 0.02
local MESH = tes3.loadMesh("tew\\Vapourmist\\vapourcloud.nif")
local HEIGHT = 6000
local SIZES = {1340, 1500, 1620, 1740, 1917, 2100, 2450, 2500, 2600 }
local WtC = tes3.worldController.weatherController

local NAME_MAIN = "tew_Clouds"
local NAME_EMITTER = "tew_Clouds_Emitter"
local NAME_PARTICLE_SYSTEMS = {
	"tew_Clouds_ParticleSystem_1",
	"tew_Clouds_ParticleSystem_2",
	"tew_Clouds_ParticleSystem_3"
}

-->>>---------------------------------------------------------------------------------------------<<<--
-- Structures

local toRemove = {}
local currentClouds = {}

local fromRegion, toRegion, fromWeather, toWeather, recolourRegistered

-->>>---------------------------------------------------------------------------------------------<<<--
-- Functions

local function getCutoffDistance(drawDistance)
	return CELL_SIZE * drawDistance / 10
end

local function isAvailable(weatherName)
	return not config.blockedCloud[weatherName]
	and config.cloudyWeathers[weatherName]
end

local function isPlayerClouded(cloudMesh)
	local mp = tes3.mobilePlayer
	local drawDistance = mge.distantLandRenderConfig.drawDistance
	return mp.position:distance(cloudMesh.translation) < (getCutoffDistance(drawDistance))
end

local function updateToRemove(cloudMesh)
	table.insert(toRemove, cloudMesh)
end

local function addClouds(cloudMesh)

end

local function detachAll()
	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]
	for _, node in pairs(vfxRoot.children) do
		if node and node.name == NAME_MAIN then
			vfxRoot:detachChild(node)
		end
	end
	currentClouds = {}
end

local function appcullAll()
	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]
	for _, node in pairs(vfxRoot.children) do
		if node and node.name == NAME_MAIN then
			local emitter = node:getObjectByName(NAME_EMITTER)
			if emitter.appCulled ~= true then
				emitter.appCulled = true
				emitter:update()
				node:update()
				timer.start{
					type = timer.simulate,
					duration = MAX_LIFESPAN,
					iterations = 1,
					persistent = false,
					callback = function() updateToRemove(node) end
				}
			end
		end
	end
end

local function waitingCheck()
	local mp = tes3.mobilePlayer
	if (not mp) or (mp and (mp.waiting or mp.traveling)) then
		toWeather = WtC.nextWeather or WtC.currentWeather
		if not (isAvailable(toWeather)) then
			debugLog("Player waiting or travelling and clouds not available.")
			detachAll()
		end
	end
end

function clouds.onWaitMenu(e)
	local element = e.element
	element:registerAfter(tes3.uiEvent.destroy, function()
		waitingCheck()
	end)
end


function clouds.onWeatherChanged()
	toWeather = WtC.nextWeather or WtC.currentWeather
	fromWeather = fromWeather or WtC.currentWeather

	if not isAvailable(toWeather) then
		appcullAll()
	end

	--[[
		if WtC.nextWeather and WtC.transitionScalar < 0.6 then
			debugLog("Weather transition in progress. Adding fog in a bit.")
			timer.start {
				type = timer.game,
				iterations = 1,
				duration = 0.2,
				callback = function() fogService.addFog(options) end
			}
		else
			-- If transition scalar is high enough or we're not transitioning at all --
			fogService.addFog(options) -- Maybe cleanInactiveFog again? To make sure we catch any edge teleporting cases etc.
		end
	]]
end

local function onTimerTick()

end

local function startTimer()
	timer.start{
		duration = TIMER_DURATION,
		callback = onTimerTick,
		iterations = -1,
		type = timer.game,
		persist = false
	}
end

-- Register events, timers and reset values --
local function onLoaded()
	-- To ensure we don't end up reregistering the event --
	if not recolourRegistered then
		event.register(tes3.event.enterFrame, reColour)
		recolourRegistered = true
	end
	startTimer()
	fromWeather = nil
	fromRegion = nil
	detachAll()
end

return clouds