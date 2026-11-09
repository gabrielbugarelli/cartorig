-- Pure Scene tree projection. This module never touches Fusion, files, or UI.
-- Render order is global; organizational nesting never changes compositing.
local M={}
local categories={
    {role="Base Map",label="Base Map"},
    {role="Camera",label="Camera"},
    {role="Region",label="Regions"},
    {role="Route",label="Routes"},
    {role="Marker",label="Markers"},
    {role="Label",label="Labels"}
}
function M.build(objects)
    assert(type(objects)=="table","Scene tree needs objects")
    local byId,groups,roots={}, {},{}
    for _,entry in ipairs(objects) do
        assert(type(entry.id)=="string" and entry.id~="","Invalid tree object ID")
        assert(not byId[entry.id],"Duplicate Scene ID")
        byId[entry.id]=entry
        if entry.role=="Group" then
            groups[entry.id]={kind="group",id=entry.id,name=entry.name,
                role="Group",children={}}
        end
    end
    local categoriesByRole={}
    for _,category in ipairs(categories) do
        local node={kind="category",id="category:"..category.role,
                    name=category.label,children={}}
        categoriesByRole[category.role]=node
        roots[#roots+1]=node
    end
    local groupRoot={kind="category",id="category:Group",
                     name="Groups",children={}}
    roots[#roots+1]=groupRoot
    for _,entry in ipairs(objects) do
        if entry.role=="Group" then
            local group=groups[entry.id]
            group.locked=entry.locked;group.visible=entry.visible;group.z=entry.z
            groupRoot.children[#groupRoot.children+1]=group
        else
            local parent=entry.parent and groups[entry.parent] or nil
            local category=categoriesByRole[entry.role]
            assert(category,"Unknown Scene object type: "..tostring(entry.role))
            local target=parent or category
            target.children[#target.children+1]={
                kind="object",id=entry.id,role=entry.role,name=entry.name,
                locked=entry.locked,visible=entry.visible,z=entry.z,
                parent=entry.parent
            }
        end
    end
    for _,root in ipairs(roots) do
        table.sort(root.children,function(a,b)
            if a.z==b.z then return a.id<b.id end
            return (a.z or 0)<(b.z or 0)
        end)
    end
    return roots
end
function M.eligible(ids,lookup,action)
    assert(type(ids)=="table" and type(lookup)=="table","Invalid selection")
    local checked,results={ },{}
    for _,id in ipairs(ids) do
        assert(type(id)=="string" and id~="","Invalid selection object ID")
        if not checked[id] then
            checked[id]=true
            local object=lookup[id]
            assert(object and object.role,"Selection no longer exists in Scene")
            if (action=="delete" or action=="move" or action=="group") and
               (object.role=="Base Map" or object.role=="Camera") then
                error("Base Map and Camera are protected objects")
            end
            results[#results+1]=object
        end
    end
    assert(#results>0,"Select at least one CartoRig object")
    return results
end
return M
