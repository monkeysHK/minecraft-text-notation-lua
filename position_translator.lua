local common = require("common")
local parsetree = require("parsetree")

local positionTranslator = {}




local function precomputePositionMap(input, length)
   local positionMap = {}
   local line = 1
   local col = 0
   for i = 1, length do
      col = col + 1
      positionMap[i] = common.Position.new(i, line, col)
      local ch = input:sub(i, i)
      if ch == "\n" then
         line = line + 1
         col = 0
      end
   end
   positionMap[length + 1] = common.Position.new(length + 1, line, col + 1)
   return positionMap
end

local function toGlobalPositionMap(positionMap, parentPosition)
   local newPositionMap = {}

   for _, position in ipairs(positionMap) do
      newPositionMap[#newPositionMap + 1] = position:toGlobalPosition(parentPosition)
   end

   return newPositionMap
end

local function computeUnescapedGlobalPositionMap(
   text,
   globalPosition,
   startOffset,
   validEscapes,
   readUntilChars)


   local positionMap = precomputePositionMap(text, #text)
   positionMap = toGlobalPositionMap(positionMap, globalPosition)


   local unescapedGlobalPositionMap = {}

   local pos = 1 + startOffset

   while pos <= #text do
      local ch = text:sub(pos, pos)

      local reachedTheEnd = readUntilChars[ch]
      if reachedTheEnd then
         break
      end

      local isEscape = ch == "\\"
      if isEscape then
         local escapeSequence = text:sub(pos, pos + 1)

         local escapeResult = validEscapes[escapeSequence]
         if escapeResult then
            assert(#escapeResult == 1)
            unescapedGlobalPositionMap[#unescapedGlobalPositionMap + 1] = positionMap[pos]
            pos = pos + (1 + 1)
         else

            unescapedGlobalPositionMap[#unescapedGlobalPositionMap + 1] = positionMap[pos]
            pos = pos + 1
         end

      else
         unescapedGlobalPositionMap[#unescapedGlobalPositionMap + 1] = positionMap[pos]
         pos = pos + 1

      end

   end

   local nextPosition = positionMap[pos]
   unescapedGlobalPositionMap[#unescapedGlobalPositionMap + 1] = nextPosition

   return unescapedGlobalPositionMap

end

local function getUnescapedGlobalPositionMapForUnquoted(text, parentPosition)
   local validEscapes = {}

   local readUntilChars = {
      [':'] = true,
      ['>'] = true,
   }

   local result = computeUnescapedGlobalPositionMap(
   text,
   parentPosition,
   0,
   validEscapes,
   readUntilChars)


   return result
end

local function getUnescapedGlobalPositionMapForSingleQuoted(text, parentPosition)
   assert(text:sub(1, 1) == "'")
   assert(text:sub(#text, #text) == "'")

   local validEscapes = {
      ["\\'"] = "'",
      ['\\\\'] = '\\',
   }
   local readUntilChars = {
      ["'"] = true,
   }

   local result = computeUnescapedGlobalPositionMap(
   text,
   parentPosition,
   1,
   validEscapes,
   readUntilChars)


   return result
end

local function getUnescapedGlobalPositionMapForDoubleQuoted(text, parentPosition)
   assert(text:sub(1, 1) == '"')
   assert(text:sub(#text, #text) == '"')

   local validEscapes = {
      ['\\"'] = '"',
      ['\\\\'] = '\\',
   }
   local readUntilChars = {
      ['"'] = true,
   }

   local result = computeUnescapedGlobalPositionMap(
   text,
   parentPosition,
   1,
   validEscapes,
   readUntilChars)


   return result
end

local function getUnescapedGlobalPositionMapForTagArg(text, parentPosition)
   local firstChar = text:sub(1, 1)
   if firstChar == '"' then
      return getUnescapedGlobalPositionMapForDoubleQuoted(text, parentPosition)
   end
   if firstChar == "'" then
      return getUnescapedGlobalPositionMapForSingleQuoted(text, parentPosition)
   end
   return getUnescapedGlobalPositionMapForUnquoted(text, parentPosition)
end

local function convertNodePositions(node, unescapedGlobalPositionMap)
   local function convertComponents(components)
      for _, component in ipairs(components) do
         convertNodePositions(component, unescapedGlobalPositionMap)
      end
   end

   local indexIsOutOfString = node.position.index > #unescapedGlobalPositionMap
   assert(not indexIsOutOfString)
   node.position = unescapedGlobalPositionMap[node.position.index]

   if node.kind == "MinecraftTextNode" then
      convertComponents(node.components)

   elseif node.kind == "PlainTextNode" then


   elseif node.kind == "NewlineNode" then


   elseif node.kind == "NamedColorNode" then
      convertComponents(node.components)

   elseif node.kind == "HexColorNode" then
      convertComponents(node.components)

   elseif node.kind == "DecorationNode" then
      convertComponents(node.components)

   elseif node.kind == "ShowTextNode" then
      convertComponents(node.components)
      convertNodePositions(node.tooltip, unescapedGlobalPositionMap)

   else
      error("This should not be reached")
   end
end

local function convertProblemPositions(problems, unescapedGlobalPositionMap)
   for i, problem in ipairs(problems) do
      local newPosition = unescapedGlobalPositionMap[problem.position.index]
      problems[i].position = newPosition
   end
end

function positionTranslator.convertPositions(node, warnings, strictProblems, parentPosition, originalTagArgString)
   local unescapedGlobalPositionMap = getUnescapedGlobalPositionMapForTagArg(originalTagArgString, parentPosition)

   convertNodePositions(node, unescapedGlobalPositionMap)

   convertProblemPositions(warnings, unescapedGlobalPositionMap)

   convertProblemPositions(strictProblems, unescapedGlobalPositionMap)
end

return positionTranslator
