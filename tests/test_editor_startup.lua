-- Execute real menu entry in a simulated Fusion UIManager: window must open before map generation.
local root=assert(arg[1],'project root required')
local win, shown, create_called, before, after=nil,false,false,nil,nil
local function element(kind, info)
  info=info or {};info.__kind=kind
  if kind=='Tree' then
    info.Clear=function(self)self.rows={} end
    info.NewItem=function()return {Text={}} end
    info.AddTopLevelItem=function(self,item)self.rows=self.rows or {};self.rows[#self.rows+1]=item end
    info.CurrentItem=function()return nil end
  elseif kind=='ComboBox' then
    info.AddItem=function(self,item)self.items=self.items or {};self.items[#self.items+1]=item end
  end
  return info
end
local ui=setmetatable({},{__index=function(_,k)return function(self,info)return element(k,info)end end})
local function collect(node,items)
  if type(node)~='table' then return end
  if node.ID then items[node.ID]=node end
  for _,v in pairs(node) do if type(v)=='table' then collect(v,items) end end
end
local comp={CurrentTime=0}
function comp:GetToolList()return {} end
function comp:FindTool()return nil end
function comp:GetData()return nil end
function comp:AddTool()create_called=true;error('MUST_NOT_CREATE_AT_STARTUP') end
_G.comp=comp;_G.fusion={UIManager=ui,GetCurrentComp=function()return comp end};_G.fu=_G.fusion
_G.bmd={UIDispatcher=function()
  return {
    AddWindow=function(self,props,layout)
      local items={};collect(layout,items)
      local w={On=setmetatable({},{__index=function(t,k)local v={};rawset(t,k,v);return v end})}
      function w:GetItems()return items end
      function w:Show()shown=true;before=items.CR_Status.Text end
      function w:Hide()end
      win=w;return w
    end,
    RunLoop=function(self)
      assert(shown and not create_called,'UI must open before building map')
      assert(win:GetItems().CR_CreateScene,'Create Map button missing')
      assert(before:find('Create Map'),'Missing startup instructions')
      win.On.CR_CreateScene.Clicked()
      after=win:GetItems().CR_Status.Text
      assert(after:find('ERROR:',1,true),'Errors must be shown in UI')
      assert(after:find('MediaOut',1,true),'Must diagnose missing MediaOut')
    end,
    ExitLoop=function()end,
  }
end}
dofile(root..'/fusion/CartoRig Fusion-first.lua')
assert(shown and not create_called,'Must never build map before opening editor')
assert(after and after:find('ERROR:',1,true),'Missing map-creation error')
print('PASS: editor visible before map creation, errors shown')
