-- Interior fog module
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

local fromRegion, toRegion, fromWeather, toWeather

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

function clouds.onTimerTick()
	-- To a different function to reuse
	local mp = tes3.mobilePlayer
	if (not mp) or (mp and (mp.waiting or mp.traveling)) then
		toWeather = WtC.nextWeather or WtC.currentWeather
		-- Remove clouds after waiting/travelling if conditions changed --
		if not (isAvailable(toWeather)) then
			debugLog("Player waiting or travelling and clouds not available.")
			detachAll()
		end
		return
	end
end

function clouds.onWeatherChanged()
	-- TODO: remove all but with appcull if not available here
end

return clouds