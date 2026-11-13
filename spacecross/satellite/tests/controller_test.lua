local Satellite = require("spacecross.satellite.controller")
local H = require("tests.support")
local Platform = require("tests.stubs.platform")
local codec = require("spacecross.core.codec")

local function heartbeat_whitelist_cache_and_directional_attack_are_bounded()
  local p, beats, detonated = Platform.new(), 0, false
  p.directories["/cache"] = true
  local crypto = {
    encrypt = function(_, data) return "sealed:" .. data end,
    decrypt = function(_, data) if data:sub(1, 7) == "sealed:" then return data:sub(8) end; return nil, "BAD_CIPHER" end,
  }
  local auxiliary = 0
  local satellite = Satellite.new({event = p.event, clock = p.clock, fs = p.fs, crypto = crypto, codec = codec,
    sendHeartbeat = function() beats = beats + 1; return true end,
    fetchWhitelist = function() return {"friendly"} end,
    scan = function(range) assert(range == 80); return {{id = "friendly"}, {id = "hostile", x = 8, y = 3, z = -1}} end,
    position = function() return {x = 2, y = 1, z = 2} end,
    activateAuxiliaryCharges = function(target, vector, count)
      assert(target.id == "hostile" and vector.x == 6 and vector.y == 2 and vector.z == -3 and count == 6)
      auxiliary = auxiliary + 1; return true
    end,
    detonateCentralCharge = function(target) assert(target.id == "hostile"); detonated = true; return true end,
  }, {id = "sat-1", heartbeatInterval = 10, range = 80, mode = "charges", cachePath = "/cache/whitelist"})
  assert(satellite:start() and beats == 1)
  assert(p.files["/cache/whitelist"]:sub(1, 7) == "sealed:")
  assert(satellite:scan()[2].id == "hostile")
  local denied, denyErr = satellite:attack({id = "friendly"})
  assert(denied == nil and denyErr == "WHITELISTED_TARGET")
  assert(satellite:attack({id = "hostile", x = 8, y = 3, z = -1}))
  assert(auxiliary == 1 and detonated and satellite.state == "armed")
  p:advance(10)
  assert(beats == 2 and satellite:snapshot().lastHeartbeat == 10)
  assert(satellite:stop() and not next(p.timers))
  return H.truth(not p.errors[1])
end

local function cache_never_writes_without_encryption()
  local p = Platform.new()
  p.directories["/cache"] = true
  local satellite = Satellite.new({event = p.event, clock = p.clock, fs = p.fs, codec = codec,
    sendHeartbeat = function() return true end}, {cachePath = "/cache/list"})
  satellite:start()
  local ok, err = satellite:updateWhitelist({"owner"})
  assert(ok == nil and err == "ENCRYPTION_UNAVAILABLE" and p.files["/cache/list"] == nil)
  satellite:stop()
  return H.truth(true)
end

local function encrypted_cache_restores_whitelist_for_offline_operation()
  local p = Platform.new(); p.directories["/cache"] = true
  local crypto = {
    encrypt = function(_, data) return "sealed:" .. data end,
    decrypt = function(_, data) return data:sub(8) end,
  }
  local first = Satellite.new({event=p.event,clock=p.clock,fs=p.fs,crypto=crypto,codec=codec,
    sendHeartbeat=function() return true end}, {cachePath="/cache/restore"})
  first:start(); assert(first:updateWhitelist({"trusted"})); first:stop()
  local second = Satellite.new({event=p.event,clock=p.clock,fs=p.fs,crypto=crypto,codec=codec,
    sendHeartbeat=function() return nil,"offline" end}, {cachePath="/cache/restore"})
  second:start()
  local ok,err=second:attack({id="trusted"})
  assert(ok==nil and err=="WHITELISTED_TARGET")
  assert(second:snapshot().whitelistReady and second:snapshot().whitelistCount==1)
  second:stop()
  return H.truth(true)
end

local function autonomous_scan_attacks_only_targets_outside_loaded_whitelist()
  local p, attacked, alerted = Platform.new(), {}, 0
  local satellite = Satellite.new({event=p.event,clock=p.clock,sendHeartbeat=function() return true end,
    fetchWhitelist=function() return {"friend"} end,
    scan=function() return {{id="friend"},{id="hostile",x=9,y=2,z=3}} end,
    sendAttackAlert=function(alert) assert(alert.target.id=="hostile"); alerted=alerted+1; return true end,
    jumpToTarget=function(target) attacked[#attacked+1]="jump:"..target.id; return true end,
    detonateCentralCharge=function(target) attacked[#attacked+1]="detonate:"..target.id; return true end},
    {modeScan=true,autoAttack=true})
  assert(satellite:start())
  assert(attacked[1]=="jump:hostile" and attacked[2]=="detonate:hostile" and alerted==1)
  assert(satellite:snapshot().targets[1].id=="friend" and satellite:snapshot().state=="armed")
  satellite:stop()
  return H.truth(not next(p.timers))
end

local all_tests = {
  {test_name = "heartbeat_whitelist_cache_and_directional_attack_are_bounded", test = heartbeat_whitelist_cache_and_directional_attack_are_bounded},
  {test_name = "cache_never_writes_without_encryption", test = cache_never_writes_without_encryption},
  {test_name = "encrypted_cache_restores_whitelist_for_offline_operation", test = encrypted_cache_restores_whitelist_for_offline_operation},
  {test_name = "autonomous_scan_attacks_only_targets_outside_loaded_whitelist", test = autonomous_scan_attacks_only_targets_outside_loaded_whitelist},
}
return all_tests
