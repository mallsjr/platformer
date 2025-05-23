function love.load()
  love.window.setMode(1000, 768)
  love.graphics.setDefaultFilter("nearest", "nearest")

  anim8 = require("libraries/anim8/anim8")
  sti = require("libraries/Simple-Tiled-Implementation/sti")
  cameraFile = require("libraries/hump/camera")

  cam = cameraFile()

  sounds = {}
  sounds.jump = love.audio.newSource("audio/jump.wav", "static")
  sounds.music = love.audio.newSource("audio/music.mp3", "stream")
  sounds.music:setLooping(true)
  sounds.music:setVolume(0.5)

  sounds.music:play()

  sprites = {}
  sprites.playerSheet = love.graphics.newImage("sprites/playerSheet.png")
  sprites.enemySheet = love.graphics.newImage("sprites/enemySheet.png")
  sprites.background = love.graphics.newImage("sprites/background.png")
  sprites.coinSheet = love.graphics.newImage("sprites/coin.png")

  local grid = anim8.newGrid(614, 564, sprites.playerSheet:getWidth(), sprites.playerSheet:getHeight())
  local enemyGrid = anim8.newGrid(100, 70, sprites.enemySheet:getWidth(), sprites.enemySheet:getHeight())
  local coinGrid = anim8.newGrid(16, 16, sprites.coinSheet:getWidth(), sprites.coinSheet:getHeight())

  animations = {}
  animations.idle = anim8.newAnimation(grid("1-15", 1), 0.05)
  animations.jump = anim8.newAnimation(grid("1-7", 2), 0.05)
  animations.run = anim8.newAnimation(grid("1-15", 3), 0.05)
  animations.enemy = anim8.newAnimation(enemyGrid("1-2", 1), 0.03)
  animations.coin = anim8.newAnimation(coinGrid("1-4", 1), 0.25)

  wf = require("libraries/windfield/windfield/")
  world = wf.newWorld(0, 800, false)
  world:setQueryDebugDrawing(true)

  world:addCollisionClass("Platform")
  world:addCollisionClass("Coin")
  world:addCollisionClass("Player" --[[, { ignores = { "Platform" } } ]])
  world:addCollisionClass("Danger", { ignores = { "Danger", "Coin" } })

  require("player")
  require("enemy")
  require("libraries/show")

  danger = world:newRectangleCollider(-500, 800, 5000, 50, {
    collision_class = "Danger",
  })
  danger:setType("static")

  platforms = {}
  coins = {}

  flagX = 0
  flagY = 0

  saveData = {}
  saveData.currentLevel = "level1"

  -- Initialize player score
  playerScore = 0
  font = love.graphics.newFont(48)

  if love.filesystem.getInfo("data.lua") then
    local data = love.filesystem.load("data.lua")
    data()
  end

  loadMap(saveData.currentLevel)
end

function love.update(dt)
  --update
  world:update(dt)
  gameMap:update(dt)
  playerUpdate(dt)
  updateEnemies(dt)
  animations.coin:update(dt)

  local px, _ = player:getPosition()
  cam:lookAt(px, love.graphics.getHeight() / 2)

  local colliders = world:queryCircleArea(flagX, flagY, 10, { "Player" })
  if #colliders > 0 then
    if saveData.currentLevel == "level1" then
      loadMap("level2")
    else
      loadMap("level1")
    end
  end

  -- Coin collection logic - using physics queries
  for i = #coins, 1, -1 do
    local coin = coins[i]
    local coinX, coinY = coin:getPosition()

    -- Check if player is colliding with coin
    local playerColliders = world:queryRectangleArea(coinX - 8, coinY - 8, 16, 16, { "Player" })

    if #playerColliders > 0 then
      -- Player is touching the coin, collect it
      playerScore = playerScore + 100
      coin:destroy() -- Remove coin from physics world
      table.remove(coins, i) -- Remove from coins table
      -- You could add a sound effect here
    end
  end
end

function love.draw()
  love.graphics.draw(sprites.background, 0, 0)
  cam:attach()
  gameMap:drawLayer(gameMap.layers["Tile Layer 1"])
  -- world:draw() -- Don't want this enabled in actual game but helpful in debugging
  drawPlayer()
  drawEnemies()

  for _, c in ipairs(coins) do
    local cx, cy = c:getPosition()
    animations.coin:draw(sprites.coinSheet, cx, cy, nil, 2, 2, 16, 16)
  end
  cam:detach()

  -- Draw player score in the top left corner
  love.graphics.setColor(1, 1, 1) -- White color
  love.graphics.setFont(font)
  love.graphics.print("Score: " .. playerScore, 10, 10)
end

function love.keypressed(key)
  if key == "up" or key == "space" then
    if player.grounded then
      player:applyLinearImpulse(0, -4000)
      sounds.jump:play()
    end
  end
end

function spawnPlatform(x, y, width, height)
  if width > 0 and height > 0 then
    local platform = world:newRectangleCollider(x, y, width, height, {
      collision_class = "Platform",
    })
    platform:setType("static")
    table.insert(platforms, platform)
  end
end

function spawnCoin(x, y, width, height)
  if width > 0 and height > 0 then
    local coin = world:newRectangleCollider(x, y, width, height, {
      collision_class = "Coin",
    })
    coin:setType("static")
    coin:setSensor(true) -- Make it a sensor so player passes through
    table.insert(coins, coin)
  end
end

function destroyAll()
  local i = #platforms
  while i > -1 do
    if platforms[i] ~= nil then
      platforms[i]:destroy()
    end
    table.remove(platforms, i)
    i = i - 1
  end

  local j = #enemies
  while j > -1 do
    if enemies[j] ~= nil then
      enemies[j]:destroy()
    end
    table.remove(enemies, j)
    j = j - 1
  end

  local c = #coins
  while c > -1 do
    if coins[c] ~= nil then
      coins[c]:destroy()
    end
    table.remove(coins, c)
    c = c - 1
  end
end

function loadMap(mapName)
  saveData.currentLevel = mapName
  love.filesystem.write("data.lua", table.show(saveData, "saveData"))
  destroyAll()
  gameMap = sti("maps/" .. mapName .. ".lua")

  for _, obj in pairs(gameMap.layers["Platforms"].objects) do
    spawnPlatform(obj.x, obj.y, obj.width, obj.height)
  end
  for _, obj in pairs(gameMap.layers["coins"].objects) do
    spawnCoin(obj.x, obj.y, obj.width, obj.height)
  end
  for _, obj in pairs(gameMap.layers["enemies"].objects) do
    spawnEnemey(obj.x, obj.y)
  end
  for _, obj in pairs(gameMap.layers["flag"].objects) do
    flagX = obj.x
    flagY = obj.y
  end
  for _, obj in pairs(gameMap.layers["start"].objects) do
    playerStartX = obj.x
    playerStartY = obj.y
  end
  player:setPosition(playerStartX, playerStartY)
end
