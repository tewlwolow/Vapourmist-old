-- Clouds module
-->>>---------------------------------------------------------------------------------------------<<<--

-- Imports
local clouds = {}
local util = require("tew.Vapourmist.components.util")
local debugLog = util.debugLog
local config = require("tew.Vapourmist.config")

-->>>---------------------------------------------------------------------------------------------<<<--
-- Constants

local TIMER_DURATION = 0.1

local CELL_SIZE = 8192

local MIN_LIFESPAN = 12
local MAX_LIFESPAN = 25

local MIN_DEPTH = 500
local MAX_DEPTH = 3400

local MIN_BIRTHRATE = 1.8
local MAX_BIRTHRATE = 3.0

local MIN_SPEED = 15

local CUTOFF_COEFF = 1.5

local HEIGHTS = {5760, 5900, 6000, 6100, 6200, 6800}
local SIZES = {1340, 1500, 1620, 1740, 1917, 2100, 2450, 2500, 2600}

local MESH = tes3.loadMesh("tew\\Vapourmist\\vapourcloud.nif")
local NAME_MAIN = "tew_Clouds"
local NAME_EMITTER = "tew_Clouds_Emitter"
local NAME_PARTICLE_SYSTEMS = {
	"tew_Clouds_ParticleSystem_1",
	"tew_Clouds_ParticleSystem_2",
	"tew_Clouds_ParticleSystem_3"
}

-->>>---------------------------------------------------------------------------------------------<<<--
-- Structures

local tracker, removeQueue = {}, {}

local toWeather, recolourRegistered

local WtC = tes3.worldController.weatherController

-->>>---------------------------------------------------------------------------------------------<<<--
-- Functions


local function getCloudPosition(cell)
	local average = 0
	local denom = 0

	for stat in cell:iterateReferences() do
		average = average + stat.position.z
		denom = denom + 1
	end

	math.randomseed(os.time())
	local height = HEIGHTS[math.random(#HEIGHTS)]

	if average == 0 or denom == 0 then
		return height
	else
		return (average / denom) + height
	end
end

local function isAvailable(weather)
	local weatherName = weather.name
	return not config.blockedCloud[weatherName]
	and config.cloudyWeathers[weatherName]
end

local function getParticleSystemSize(drawDistance)
	local distantFog = mge.weather.getDistantFog(WtC.currentWeather.index)
	local fogDistance = 1
	if distantFog then
		fogDistance = distantFog.distance
	end
	return (CELL_SIZE * drawDistance * fogDistance)
end

local function getCutoffDistance(drawDistance)
	local distantFog = mge.weather.getDistantFog(WtC.currentWeather.index)
	local fogDistance = 1
	if distantFog then
		fogDistance = distantFog.distance
	end
	return (CELL_SIZE * drawDistance * fogDistance) / CUTOFF_COEFF
end

local function isPlayerClouded(cloudMesh)
	debugLog("Checking if player is clouded.")
	local mp = tes3.mobilePlayer
	local playerPos = mp.position:copy()
	local drawDistance = mge.distantLandRenderConfig.drawDistance
	return playerPos:distance(cloudMesh.translation:copy()) < (getCutoffDistance(drawDistance))
end

local function addToTracker(cloud)
	table.insert(tracker, cloud)
	debugLog("Clouds added to tracker.")
end

local function removeFromTracker(cloud)
	local pos = table.find(tracker, cloud)
	if pos then
		table.remove(tracker, pos)
		debugLog("Clouds removed from tracker.")
	else
		tracker = {}
	end
end

local function addToRemoveQueue(cloud)
	table.insert(removeQueue, cloud)
	debugLog("Clouds added to removal queue.")
end

local function removeFromRemoveQueue(cloud)
	local pos = table.find(removeQueue, cloud)
	if pos then
		table.remove(removeQueue, pos)
		debugLog("Clouds removed from removal queue.")
	else
		removeQueue = {}
	end
end

local function detach(vfxRoot, node)
	vfxRoot:detachChild(node)
	debugLog("Cloud detached.")
	removeFromRemoveQueue(node)
end

function clouds.detachAll()
	debugLog("Detaching all clouds.")
	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]
	for _, node in pairs(vfxRoot.children) do
		if node and node.name == NAME_MAIN then
			detach(vfxRoot, node)
		end
	end
	tracker = {}
end

local function switchAppCull(node, bool)
	local emitter = node:getObjectByName(NAME_EMITTER)
	if (emitter ~= bool) then
		emitter.appCulled = bool
		emitter:update()
		-- node:update()
	end
end

local function showCloud(node)
	switchAppCull(node, false)
end

local function appCull(node)
	local emitter = node:getObjectByName(NAME_EMITTER)
	if not (emitter.appCulled) then
		switchAppCull(node, true)
		timer.start{
			type = timer.simulate,
			duration = MAX_LIFESPAN,
			iterations = 1,
			persistent = false,
			callback = function() addToRemoveQueue(node) end
		}
		debugLog("Clouds appculled.")
		removeFromTracker(node)
	else
		debugLog("Clouds already appculled. Skipping.")
	end
end

local function appCullAll()
	debugLog("Appculling all clouds.")
	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]
	for _, node in pairs(vfxRoot.children) do
		if node and node.name == NAME_MAIN then
			appCull(node)
		end
	end
end

local function getCloudColourMix(fogComp, skyComp)
	return math.lerp(fogComp, skyComp, 0.2)
end

local function getBleachedColour(comp)
	return math.clamp(math.lerp(comp, 1.0, 0.04), 0.03, 0.88)
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
	return {
		colours = {
			r = getBleachedColour(weatherColour.r),
			g = getBleachedColour(weatherColour.g),
			b = getBleachedColour(weatherColour.b)
		},
		angle = WtC.windVelocityCurrWeather:normalized():copy().y * math.pi * 0.5,
		speed = math.max(WtC.currentWeather.cloudsSpeed * config.speedCoefficient, MIN_SPEED)
	}
end

local function reColour()
	if not tracker then return end
	if table.empty(tracker) then return end
	local output = getOutputValues()
	local cloudColour = output.colours
	local speed = output.speed
	local angle = output.angle

	for _, cloud in ipairs(tracker) do
		for _, name in ipairs(NAME_PARTICLE_SYSTEMS) do
			local particleSystem = cloud:getObjectByName(name)

			local controller = particleSystem.controller
			local colorModifier = controller.particleModifiers

			controller.speed = speed
			controller.planarAngle = angle

			for _, key in pairs(colorModifier.colorData.keys) do
				key.color.r = cloudColour.r
				key.color.g = cloudColour.g
				key.color.b = cloudColour.b
			end

			local materialProperty = particleSystem.materialProperty
			materialProperty.emissive = cloudColour
			materialProperty.specular = cloudColour
			materialProperty.diffuse = cloudColour
			materialProperty.ambient = cloudColour

			particleSystem:update()
			particleSystem:updateProperties()
			particleSystem:updateEffects()
			cloud:update()
			cloud:updateProperties()
			cloud:updateEffects()
		end
	end
end

local function deployEmitter(particleSystem)
	math.randomseed(os.time())
	local drawDistance = mge.distantLandRenderConfig.drawDistance

	local controller = particleSystem.controller

	local birthRate = math.random(MIN_BIRTHRATE, MAX_BIRTHRATE) * drawDistance
	controller.birthRate = birthRate
	controller.useBirthRate = true

	local lifespan = math.random(MIN_LIFESPAN, MAX_LIFESPAN)
	controller.lifespan = lifespan
	controller.emitStopTime = lifespan

	local effectSize = getParticleSystemSize(drawDistance)

	controller.emitterWidth = effectSize
	controller.emitterHeight = effectSize
	controller.emitterDepth = math.random(MIN_DEPTH, MAX_DEPTH)

	controller.initialSize = SIZES[math.random(#SIZES)]
	debugLog("Emitter deployed.")
end

local function addClouds()
	debugLog("Adding clouds.")
	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]
	local cell = tes3.getPlayerCell()

	local mp = tes3.mobilePlayer
	if not mp or not mp.position then return end

	local playerPos = mp.position:copy()

	local cloudPosition = tes3vector3.new(
		playerPos.x,
		playerPos.y,
		getCloudPosition(cell)
	)

	local cloudMesh = MESH:clone()
	cloudMesh:clearTransforms()
	cloudMesh.translation = cloudPosition

	vfxRoot:attachChild(cloudMesh)

	local cloudNode
	for _, node in pairs(vfxRoot.children) do
		if node then
			if node.name == NAME_MAIN then
				if not table.find(removeQueue, node) then
					cloudNode = node
				end
			end
		end
	end
	if not cloudNode then return end

	addToTracker(cloudNode)

	for _, name in ipairs(NAME_PARTICLE_SYSTEMS) do
		local particleSystem = cloudNode:getObjectByName(name)
		if particleSystem then
			deployEmitter(particleSystem)
		end
	end

	cloudMesh.appCulled = false
	cloudMesh:update()
	cloudMesh:updateProperties()
	cloudMesh:updateEffects()
	debugLog("Clouds added.")
end

local function waitingCheck()
	debugLog("Starting waiting check.")
	local mp = tes3.mobilePlayer
	if (not mp) or (mp and (mp.waiting or mp.traveling)) then
		toWeather = WtC.nextWeather or WtC.currentWeather
		if not (isAvailable(toWeather)) then
			debugLog("Player waiting or travelling and clouds not available.")
			clouds.detachAll()
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
	debugLog("Starting weather check.")
	toWeather = WtC.nextWeather or WtC.currentWeather

	if not isAvailable(toWeather) then
		appCullAll()
		return
	end

	if not table.empty(tracker) then return end

	if WtC.nextWeather and WtC.transitionScalar < 0.6 then
		debugLog("Weather transition in progress. Adding clouds in a bit.")
		timer.start {
			type = timer.game,
			iterations = 1,
			duration = 0.2,
			callback = clouds.onWeatherChanged
		}
	else
		addClouds()
	end
end

function clouds.conditionCheck()
	local cell = tes3.getPlayerCell()
	if not cell.isOrBehavesAsExterior then return end

	toWeather = WtC.nextWeather or WtC.currentWeather

	for _, node in ipairs(removeQueue) do
		local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]
		detach(vfxRoot, node)
	end

	if not table.empty(tracker) then
		debugLog("Tracker not empty. Checking distance.")
		for _, node in ipairs(tracker) do
			if not isPlayerClouded(node) then
				debugLog("Found distant cloud.")
				appCull(node)
			end
		end
	else
		if isAvailable(toWeather) then
			debugLog("Tracker is empty. Adding clouds.")
			addClouds()
		end
	end
end

local function startTimer()
	timer.start{
		duration = TIMER_DURATION,
		callback = clouds.conditionCheck,
		iterations = -1,
		type = timer.game,
		persist = false
	}
end

-- Register events, timers and reset values --
function clouds.onLoaded()
	debugLog("Game loaded.")
	if not recolourRegistered then
		event.register(tes3.event.enterFrame, reColour)
		recolourRegistered = true
	end
	startTimer()
	tracker, removeQueue = {}, {}
	clouds.detachAll()
end

return clouds