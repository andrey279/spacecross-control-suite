local Adapters=require("spacecross.satellite.adapters")
local H=require("tests.support")

local function configured_component_methods_route_payloads_without_guessing()
  local calls={}
  local components={
    radar={scan=function(range) calls.range=range; return {{id="enemy",x=5,y=6,z=7}} end},
    ship={jump=function(target) calls.jump=target.id end,position=function() return {x=1,y=2,z=3} end},
    auxiliary={fire=function(target,vector,count) calls.count=count; calls.dx=vector.x; return true end},
    central={detonate=function(target) calls.detonate=target.id; return true end},
  }
  local adapter=Adapters.new({component={proxy=function(address) return components[address] end}}, {
    radar={address="radar",scan="scan"},ship={address="ship",jump="jump",position="position"},
    charges={auxiliary={address="auxiliary",method="fire"},central={address="central",method="detonate"}},
  })
  assert(adapter:scan(32)[1].id=="enemy" and calls.range==32)
  assert(adapter:position().z==3)
  assert(adapter:jump({id="enemy"}) and calls.jump=="enemy")
  assert(adapter:auxiliary({id="enemy"},{x=4,y=4,z=4},6) and calls.count==6 and calls.dx==4)
  assert(adapter:central({id="enemy"}) and calls.detonate=="enemy")
  return H.truth(true)
end

local function unavailable_or_unconfigured_components_fail_closed()
  local adapter=Adapters.new({component={proxy=function() error("missing") end}},
    {radar={address="radar",scan="scan"}})
  local values,err=adapter:scan(16)
  assert(values==nil and err=="COMPONENT_UNAVAILABLE")
  local noPosition=Adapters.new({component={proxy=function() return {jump=function() end} end}},
    {ship={address="ship",jump="jump"}})
  local position,posErr=noPosition:position()
  assert(position==nil and posErr=="POSITION_UNAVAILABLE")
  return H.truth(not pcall(Adapters.new,{component={proxy=function() end}}, {radar={address="bad/address",scan="scan"}}))
end

local all_tests={
  {test_name="configured_component_methods_route_payloads_without_guessing",test=configured_component_methods_route_payloads_without_guessing},
  {test_name="unavailable_or_unconfigured_components_fail_closed",test=unavailable_or_unconfigured_components_fail_closed},
}
return all_tests
