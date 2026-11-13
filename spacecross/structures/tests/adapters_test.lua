local Adapters=require("spacecross.structures.adapters")
local H=require("tests.support")

local function deployment_receipt_selects_new_structure_computer()
  local calls={}
  local components={
    builder={build=function(target,index) calls.built=index; return {computerAddress="new-computer"} end,
      verify=function(target,index,receipt) calls.confirmed=receipt.computerAddress=="new-computer"; return true end},
    ["new-computer"]={install=function(program,target,index) calls.program=program; calls.installed=index; return true end},
  }
  local adapter=Adapters.new({component={proxy=function(address) return components[address] end}}, {
    builder={address="builder",deploy="build",confirm="verify"},
    computer={addressField="computerAddress",provision="install"},
  })
  local target={x=4,y=70,z=-2}
  local receipt=assert(adapter:deploy(target,1))
  assert(receipt.computerAddress=="new-computer")
  assert(adapter:provision(target,"mine-controller",1,receipt))
  assert(adapter:confirm(target,1,receipt))
  assert(calls.built==1 and calls.program=="mine-controller" and calls.installed==1 and calls.confirmed)
  return H.truth(true)
end

local function missing_receipt_and_component_fail_closed()
  local adapter=Adapters.new({component={proxy=function() error("offline") end}}, {
    builder={address="builder",deploy="build",confirm="verify"},computer={addressField="computerAddress",provision="install"},
  })
  local ok,err=adapter:provision({x=0,y=64,z=0},"mine",1,nil)
  assert(ok==nil and err=="STRUCTURE_COMPUTER_UNKNOWN")
  local deployed,deployErr=adapter:deploy({x=0,y=64,z=0},1)
  assert(deployed==nil and deployErr=="COMPONENT_UNAVAILABLE")
  return H.truth(not pcall(Adapters.new,{component={proxy=function() end},}, {
    builder={address="builder",deploy="build",confirm="verify"},computer={addressField="missing field",provision="install"},
  }))
end

local function waypoint_confirmation_method_is_mandatory()
  return H.truth(not pcall(Adapters.new,{component={proxy=function() end}}, {
    builder={address="builder",deploy="build"},computer={address="computer",provision="install"},
  }))
end

local all_tests={
  {test_name="deployment_receipt_selects_new_structure_computer",test=deployment_receipt_selects_new_structure_computer},
  {test_name="missing_receipt_and_component_fail_closed",test=missing_receipt_and_component_fail_closed},
  {test_name="waypoint_confirmation_method_is_mandatory",test=waypoint_confirmation_method_is_mandatory},
}
return all_tests
