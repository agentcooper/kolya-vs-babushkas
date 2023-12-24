import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/animation"

local gfx <const> = playdate.graphics
local point <const> = playdate.geometry.point

local TAG <const> = {
    player = 1,
    granny = 2,
    rocket = 3,
    flower = 4
}

local STATE <const> = {
    playing = 1,
    dead = 2
}

local DIRECTION <const> = {
    up = 1,
    down = 2,
    left = 3,
    right = 4,
    left_up = 5,
    left_down = 6,
    right_up = 7,
    right_down = 8
}

local directionToVector <const> = {
    [DIRECTION.up] = { 0, -1 },
    [DIRECTION.down] = { 0, 1 },
    [DIRECTION.left] = { -1, 0 },
    [DIRECTION.right] = { 1, 0 },
    [DIRECTION.left_up] = { -1, -1 },
    [DIRECTION.left_down] = { -1, 1 },
    [DIRECTION.right_up] = { 1, -1 },
    [DIRECTION.right_down] = { 1, 1 },
}

local images_granny <const> = {
    gfx.imagetable.new("images/granny_1"),
    gfx.imagetable.new("images/granny_2"),
    gfx.imagetable.new("images/granny_3")
}

local image_flower = gfx.image.new("images/flower")
local image_tree = gfx.image.new("images/tree")
local image_player = gfx.image.new("images/player_2")
local image_rocket = gfx.image.new("images/rocket")

local sounds_granny <const> = {
    playdate.sound.sample.new("sounds/granny_1"),
    playdate.sound.sample.new("sounds/granny_2")
}

local sounds_granny_dead <const> = {
    playdate.sound.sample.new("sounds/granny_dead_1"),
    playdate.sound.sample.new("sounds/granny_dead_2")
}

local sounds_fire <const> = {
    playdate.sound.sample.new("sounds/fire_1"),
    playdate.sound.sample.new("sounds/fire_2"),
    playdate.sound.sample.new("sounds/fire_3")
}

local function get_random_item(table)
    return table[math.random(1, #table)]
end

local sampleplayer_granny = playdate.sound.sampleplayer.new(sounds_granny[1])

local health = 3
local state = STATE.playing

local dx = 0
local dy = 0
local playerDirection = DIRECTION.right

local cameraX = 0
local cameraY = 0

local screenOffsetX = 0
local screenOffsetY = 0

local function new_tree()
    local sprite = gfx.sprite.new(image_tree)
    sprite:moveTo(math.random(-400, 400), math.random(-400, 400))
    sprite:setCenter(0.5, 1)
    sprite:add()
    sprite:setTag(TAG.flower)
    sprite:setZIndex(math.floor(sprite.y))
    function sprite:destroy()
        self:remove()
    end
end

local function new_flower()
    local sprite = gfx.sprite.new(image_flower)
    sprite:moveTo(math.random(-400, 400), math.random(-400, 400))
    sprite:setCenter(0.5, 1)
    sprite:add()
    sprite:setTag(TAG.flower)
    sprite:setZIndex(math.floor(sprite.y))
    function sprite:destroy()
        self:remove()
    end
end

function table.slice(tbl, first, last, step)
    local sliced = {}
    for i = first or 1, last or #tbl, step or 1 do
        sliced[#sliced + 1] = tbl[i]
    end
    return sliced
end

local function isLookingLeft(direction)
    return direction == DIRECTION.left or direction == DIRECTION.left_up or direction == DIRECTION.left_down
end

local function isLookingRight(direction)
    return direction == DIRECTION.right or direction == DIRECTION.right_up or direction == DIRECTION.right_down
end

local function new_player()
    local sprite = gfx.sprite.new(image_player)
    sprite:setCenter(0.5, 1)
    sprite:moveTo(200, 200)
    sprite:add()
    sprite:setTag(TAG.player)
    sprite:setGroups({ TAG.player })
    sprite:setCollidesWithGroups({ TAG.granny })
    sprite:setZIndex(1)
    sprite:setCollideRect(0, 0, sprite:getSize())

    local trail = {}

    function sprite:update()
        self:setZIndex(math.floor(self.y))

        if isLookingLeft(playerDirection) then
            self:setImageFlip(gfx.kImageUnflipped)
        else
            self:setImageFlip(gfx.kImageFlippedX)
        end

        table.insert(trail, 1, { x = self.x, y = self.y })
        trail = table.slice(trail, 1, 10, 1)
    end

    function sprite:overlay()
        for i = 1, #trail, 1 do
            if isLookingLeft(playerDirection) then
                gfx.drawRect(trail[i].x + 55, trail[i].y - 5, 4, 2)
                gfx.drawRect(trail[i].x - 65, trail[i].y - 5, 4, 2)
            else
                gfx.drawRect(trail[i].x + 60, trail[i].y - 5, 4, 2)
                gfx.drawRect(trail[i].x - 60, trail[i].y - 5, 4, 2)
            end
        end
    end

    function sprite:destroy()
        self:remove()
    end

    return sprite
end

local player
local reset

local function take_damage()
    if state == STATE.dead then
        return
    end

    health -= 1

    if health <= 0 then
        state = STATE.dead
        playdate.timer.performAfterDelay(2000, reset)
    end
end

local shakeTimer
local function shake()
    if shakeTimer ~= nil then
        return
    end
    take_damage()
    shakeTimer = playdate.timer.new(1000, 15, 0)
    shakeTimer.updateCallback = function(timer)
        local magnitude = math.floor(timer.value)
        screenOffsetX = math.random(-magnitude, magnitude)
        screenOffsetY = math.random(-magnitude, magnitude)
    end
    shakeTimer.timerEndedCallback = function()
        shakeTimer = nil
    end
end

local function count_grannies()
    local count = 0
    gfx.sprite.performOnAllSprites(function(sprite)
        if sprite and sprite:getTag() == TAG.granny then
            count += 1
        end
    end)
    return count
end

local function get_volume_from_distance(sprite, player)
    local sp = point.new(sprite.x, sprite.y)
    local pp = point.new(player.x, player.y)
    local distance = sp:distanceToPoint(pp)
    if distance > 450 then
        return 0
    end
    local volume = 1 / (distance / 50)
    return volume
end

local function new_granny(x, y)
    local speed = math.random() + 1
    local animation = gfx.animation.loop.new(speed * 100, get_random_item(images_granny), true)

    local sprite = gfx.sprite.new(animation:image())
    sprite:moveTo(x, y)
    sprite:setCenter(0.5, 1)
    sprite:add()
    sprite:setTag(TAG.granny)
    sprite:setGroups({ TAG.granny })
    sprite:setCollidesWithGroups({ TAG.player, TAG.rocket })
    local width, height = sprite:getSize()
    sprite:setCollideRect(20, 30, width - 20, height - 50)
    sprite:setZIndex(1)

    local function say_something()
        if sprite == nil or sampleplayer_granny:isPlaying() then
            return
        end

        local volume = get_volume_from_distance(sprite, player)
        local onTheLeft = sprite.x < player.x
        local length = 0
        if volume > 0 then
            local sample = sounds_granny[math.random(1, #sounds_granny)]
            sampleplayer_granny:setSample(sample)
            if onTheLeft then
                sampleplayer_granny:playAt(0, volume, 0);
            else
                sampleplayer_granny:playAt(0, 0, volume);
            end
            length = sample:getLength()
        end

        playdate.timer.performAfterDelay(length + 5000 + math.random(1000, 7000), say_something)
    end

    say_something()

    function sprite:update()
        self:setZIndex(math.floor(self.y))
        self:setImage(animation:image())

        local s = point.new(self.x, self.y)
        local p = point.new(player.x, player.y)
        local delta = (p - s):normalized()

        self:moveBy(delta.x * speed, delta.y * speed)
        if delta.x > 0 then self:setImageFlip(gfx.kImageFlippedX) end
        if delta.x < 0 then self:setImageFlip(gfx.kImageUnflipped) end

        if math.abs(player.y - self.y) < 10 and self:alphaCollision(player) then
            shake()
        end
    end

    function sprite:kill()
        if sampleplayer ~= nil then
            sampleplayer:stop()
        end
        get_random_item(sounds_granny_dead):playAt(0, get_volume_from_distance(sprite, player))

        sprite:destroy()
    end

    function sprite:destroy()
        sprite.update = nil
        self:remove()
    end
end

local function new_rocket()
    local vector = directionToVector[playerDirection]
    local rocket_dx = vector[1]
    local rocket_dy = vector[2]
    local speed = 8
    local start = point.new(player.x, player.y - 50)

    local sprite = playdate.graphics.sprite.new(image_rocket)
    sprite:moveTo(start.x, start.y)
    sprite:add()
    sprite:setZIndex(32767)
    sprite:setTag(TAG.rocket)
    sprite:setGroups({ TAG.rocket })
    sprite:setCollidesWithGroups({ TAG.granny })
    local width, height = sprite:getSize()
    sprite:setCollideRect(5, 10, width - 5, height - 10)

    local animationTimer = playdate.timer.new(2000, 0, 360)
    animationTimer.repeats = true
    animationTimer.updateCallback = function(timer)
        sprite:setRotation(timer.value)
    end

    sounds_fire[math.random(#sounds_fire)]:play()
    -- sound_fire_1:play()

    function sprite:destroy()
        animationTimer.updateCallback = nil
        self:remove()
    end

    function sprite:update()
        self:moveBy(rocket_dx * speed, rocket_dy * speed)

        local s = point.new(self.x, self.y)

        if s:distanceToPoint(start) > 400 then
            self:destroy()
            return
        end
    end
end

local function debug_granny()
    new_granny(100, 100)
end

local function spawn_grannies()
    local total = 3
    local center = playdate.geometry.vector2D.new(200, 200)
    for i = 1, total do
        local sector = math.floor(360 / total)
        local from = sector * (i - 1)
        local to = sector * i
        local angle = math.random(from, to)
        local v = center + playdate.geometry.vector2D.newPolar(500, angle)

        if count_grannies() < 15 then
            new_granny(v.x, v.y)
        end
    end
    playdate.timer.performAfterDelay(5000, function()
        spawn_grannies()
    end)
end

local function start()
    for i = 1, 100 do
        new_flower()
    end
    for i = 1, 10 do
        new_tree()
    end
    spawn_grannies()
    -- debug_granny()
end

reset = function()
    gfx.sprite.performOnAllSprites(function(sprite)
        sprite:destroy()
    end)

    state = STATE.playing
    health = 3

    dx = 0
    dy = 0
    playerDirection = DIRECTION.right

    cameraX = 0
    cameraY = 0

    screenOffsetX = 0
    screenOffsetY = 0
    player = new_player()

    start()
end

function playdate.AButtonDown()
    new_rocket()
end

local function getPlayerDirection(current)
    if dx == -1 and dy == 0 then
        return DIRECTION.left
    end
    if dx == 1 and dy == 0 then
        return DIRECTION.right
    end
    if dx == 0 and dy == 1 then
        if isLookingLeft(current) then
            return DIRECTION.left_down
        end
        if isLookingRight(current) then
            return DIRECTION.right_down
        end
        return DIRECTION.down
    end
    if dx == 0 and dy == -1 then
        if isLookingLeft(current) then
            return DIRECTION.left_up
        end
        if isLookingRight(current) then
            return DIRECTION.right_up
        end
        return DIRECTION.up
    end
    if dx == -1 and dy == -1 then
        return DIRECTION.left_up
    end
    if dx == -1 and dy == 1 then
        return DIRECTION.left_down
    end
    if dx == 1 and dy == 1 then
        return DIRECTION.right_down
    end
    if dx == 1 and dy == -1 then
        return DIRECTION.right_up
    end
    return DIRECTION.right
end

function playdate.leftButtonDown()
    dx -= 1
    playerDirection = getPlayerDirection(playerDirection)
end

function playdate.rightButtonDown()
    dx += 1
    playerDirection = getPlayerDirection(playerDirection)
end

function playdate.upButtonDown()
    dy -= 1
    playerDirection = getPlayerDirection(playerDirection)
end

function playdate.downButtonDown()
    dy += 1
    playerDirection = getPlayerDirection(playerDirection)
end

function playdate.leftButtonUp()
    dx += 1
end

function playdate.rightButtonUp()
    dx -= 1
end

function playdate.upButtonUp()
    dy += 1
end

function playdate.downButtonUp()
    dy -= 1
end

reset()

function playdate.update()
    playdate.timer.updateTimers()

    if state == STATE.dead then
        gfx.setDrawOffset(0, 0)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(0, 0, 400, 240)
        gfx.setColor(gfx.kColorClear)
        return
    end

    local moveX = dx * 5
    local moveY = dy * 5

    cameraX -= moveX;
    cameraY -= moveY;

    local collisions = gfx.sprite.allOverlappingSprites()
    for i = 1, #collisions do
        local collisionPair = collisions[i]
        local s1 = collisionPair[1]
        local s2 = collisionPair[2]
        -- TODO: should I always check both?
        if s1 and s2 and s1:getTag() == TAG.rocket and s2:getTag() == TAG.granny then
            s1:destroy()
            s2:kill()
        end
        if s1 and s2 and s2:getTag() == TAG.rocket and s1:getTag() == TAG.granny then
            s1:kill()
            s2:destroy()
        end
    end

    player:moveBy(moveX, moveY)
    gfx.setDrawOffset(cameraX + screenOffsetX, cameraY + screenOffsetY)

    gfx.sprite.update()
    player:overlay()
    -- playdate.drawFPS(0, 0)
end
