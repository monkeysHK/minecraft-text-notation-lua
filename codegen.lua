local parsetree = require("parsetree")

local codegen = {}











local function span(content, opt)
   local classNames = {}
   if opt.format then
      classNames[#classNames + 1] = "mcformat-" .. opt.format
   end
   if opt.class then
      classNames[#classNames + 1] = opt.class
   end
   local class = #classNames > 0 and ' class="' .. table.concat(classNames, " ") .. '"' or ""
   local style = opt.style and ' style="' .. opt.style .. '"' or ""
   return "<span" .. class .. style .. ">" .. content .. "</span>"
end

local function genComponents(components)
   local result = ""

   for _, component in ipairs(components) do
      local generateResult = codegen.generate(component)

      result = result .. generateResult
   end

   return result
end

function codegen.generate(node)
   local result = ""

   if node.kind == "MinecraftTextNode" then
      local componentResult = genComponents(node.components)
      result = result .. componentResult


   elseif node.kind == "PlainTextNode" then
      result = result .. node.content

   elseif node.kind == "NewlineNode" then
      result = result .. "<br>"

   elseif node.kind == "NamedColorNode" then
      local componentResult = genComponents(node.components)

      result = result .. span(componentResult, { format = node.color })

   elseif node.kind == "HexColorNode" then
      local componentResult = genComponents(node.components)

      result = result .. span(componentResult, { style = "color: #" .. node.color .. ";" })

   elseif node.kind == "DecorationNode" then
      local componentResult = genComponents(node.components)

      result = result .. span(componentResult, { format = node.decoration })

   elseif node.kind == "ShowTextNode" then
      local tooltipResult = codegen.generate(node.tooltip)

      local mctooltip = span(tooltipResult, { class = "mctooltip" })

      local componentResult = genComponents(node.components)

      result = result .. span(componentResult .. mctooltip, {})

   else
      error("This should not be reached")
   end

   return result
end

return codegen
