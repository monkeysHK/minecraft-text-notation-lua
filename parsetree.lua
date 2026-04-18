local common = require("common")

local parsetree = { MinecraftTextNode = {}, NewlineNode = {}, NamedColorNode = {}, HexColorNode = {}, DecorationNode = {}, ShowTextNode = {}, PlainTextNode = {} }










































































function parsetree.MinecraftTextNode.new(position, components)
   local self = setmetatable({}, { __index = parsetree.MinecraftTextNode })
   self.kind = "MinecraftTextNode"
   self.position = position
   self.components = components
   return self
end

function parsetree.NewlineNode.new(position)
   local self = setmetatable({}, { __index = parsetree.NewlineNode })
   self.kind = "NewlineNode"
   self.position = position
   return self
end

function parsetree.NamedColorNode.new(position, color, components)
   local self = setmetatable({}, { __index = parsetree.NamedColorNode })
   self.kind = "NamedColorNode"
   self.position = position
   self.color = color
   self.components = components
   return self
end

function parsetree.HexColorNode.new(position, color, components)
   assert(#color == 6)
   local self = setmetatable({}, { __index = parsetree.HexColorNode })
   self.kind = "HexColorNode"
   self.position = position
   self.color = color
   self.components = components
   return self
end

function parsetree.DecorationNode.new(position, decoration, components)
   local self = setmetatable({}, { __index = parsetree.DecorationNode })
   self.kind = "DecorationNode"
   self.position = position
   self.decoration = decoration
   self.components = components
   return self
end

function parsetree.ShowTextNode.new(position, tooltip, components)
   local self = setmetatable({}, { __index = parsetree.ShowTextNode })
   self.kind = "ShowTextNode"
   self.position = position
   self.tooltip = tooltip
   self.components = components
   return self
end

function parsetree.PlainTextNode.new(position, content)
   local self = setmetatable({}, { __index = parsetree.PlainTextNode })
   self.kind = "PlainTextNode"
   self.position = position
   self.content = content
   return self
end

return parsetree
