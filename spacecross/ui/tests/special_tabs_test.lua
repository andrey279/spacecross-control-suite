local UI=require("spacecross.ui.framework")
local GPU=require("spacecross.ui.tests.stubs.gpu")
local Satellite=require("spacecross.ui.satellite_tab")
local Structures=require("spacecross.ui.structures_tab")
local H=require("tests.support")

local function satellite_target_and_mode_actions_preserve_host_and_payload()
  local gpu,calls=GPU(),{}; gpu.width,gpu.height=60,16
  local ui=UI.new({authorize=function(p) return p=="Owner" end,request=function(ep,action,player,args)
    if action=="snapshot" then return {state="idle",mode="jump",targets={{id="enemy",x=4,y=5,z=6}}} end
    calls[#calls+1]={ep.host,action,args}; return true
  end})
  ui:addPanel("p",gpu,"screen","Owner")
  ui:addTab("p",Satellite.new({host="sat-a",model="satellite"})); assert(ui:select("p","satellite"))
  assert(ui:input("p",{"touch","screen",2,6,0,"Owner"}))
  assert(calls[1][1]=="sat-a" and calls[1][2]=="setMode" and calls[1][3].mode=="jump")
  assert(ui:input("p",{"touch","screen",2,8,0,"Owner"}))
  assert(calls[2][2]=="attack" and calls[2][3].target.id=="enemy")
  return H.truth(true)
end

local function structure_controls_expose_start_and_stop()
  local gpu,calls=GPU(),{}; gpu.width,gpu.height=40,12
  local ui=UI.new({authorize=function(p) return p=="Owner" end,request=function(ep,action)
    if action=="snapshot" then return {state="idle",phase="idle"} end
    calls[#calls+1]=action; return true
  end})
  ui:addPanel("p",gpu,"screen","Owner")
  ui:addTab("p",Structures.new({host="builder",model="structures"})); assert(ui:select("p","structures"))
  assert(ui:input("p",{"touch","screen",2,5,0,"Owner"}))
  assert(ui:input("p",{"touch","screen",2,6,0,"Owner"}))
  assert(calls[1]=="start" and calls[2]=="stop")
  return H.truth(true)
end

local all_tests={
  {test_name="satellite_target_and_mode_actions_preserve_host_and_payload",test=satellite_target_and_mode_actions_preserve_host_and_payload},
  {test_name="structure_controls_expose_start_and_stop",test=structure_controls_expose_start_and_stop},
}
return all_tests
