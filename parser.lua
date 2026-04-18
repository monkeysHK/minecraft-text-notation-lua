local common = require("common")
local parsetree = require("parsetree")
local lexer = require("lexer")
local positionTranslator = require("position_translator")

local parser = {}





local function tagMatches(startTag, endTag)
   local nameMatches = startTag.name == endTag.name

   if not nameMatches then
      return false
   end

   for i = 1, #endTag.arguments do
      local hasOpenArgument = i <= #startTag.arguments
      local argMatches = hasOpenArgument and startTag.arguments[i].content == endTag.arguments[i].content
      if not argMatches then
         return false
      end
   end

   return true
end

local function parseNewlineTag(tag, startIndex)
   local isStartTag = tag.kind == "TagToken" and not tag.isEndTag

   if not isStartTag then
      return common.ParseReject.new()
   end

   assert(tag.kind == "TagToken")
   if tag.name == "br" then
      if #tag.arguments > 0 then
         return common.ParseFail.new(common.Problem.new("too many argument in br tag", tag.position))
      end
      return common.ParseAccept.new(parsetree.NewlineNode.new(tag.position), startIndex + 1, {}, {})
   end

   return common.ParseReject.new()
end

local function parseVoidTag(tag, startIndex)
   local tagParsersToTry = { parseNewlineTag }

   for _, tagParser in ipairs(tagParsersToTry) do
      local result = tagParser(tag, startIndex)
      if result.kind == "ParseAccept" or result.kind == "ParseFail" then
         return result
      end
   end

   return common.ParseReject.new()
end

local function parseResetTag(tag, startIndex)
   local isStartTag = tag.kind == "TagToken" and not tag.isEndTag

   if not isStartTag then
      return common.ParseReject.new()
   end

   assert(tag.kind == "TagToken")
   if tag.name == "reset" then
      if #tag.arguments > 0 then
         return common.ParseFail.new(common.Problem.new("too many argument in reset tag", tag.position))
      end
      local warnings = {}
      local strictProblems = {
         common.Problem.new("reset tag is not allowed", tag.position),
      }
      return common.ParseAccept.new(true, startIndex + 1, warnings, strictProblems)
   end

   return common.ParseReject.new()
end

local function toNamedColor(color)
   local validColors = {
      black = "black",
      dark_blue = "dark_blue",
      dark_green = "dark_green",
      dark_aqua = "dark_aqua",
      dark_red = "dark_red",
      dark_purple = "dark_purple",
      gold = "gold",
      gray = "gray",
      dark_gray = "dark_gray",
      blue = "blue",
      green = "green",
      aqua = "aqua",
      red = "red",
      light_purple = "light_purple",
      yellow = "yellow",
      white = "white",
   }

   return validColors[color]
end

local function parseOpenNamedColorTag(tag, startIndex)
   local color = toNamedColor(tag.name)

   if not color then
      return common.ParseReject.new()
   end

   assert(type(color) == "string")
   if #tag.arguments > 0 then
      return common.ParseFail.new(common.Problem.new("too many argument in named color tag", tag.position))
   end

   return common.ParseAccept.new(parsetree.NamedColorNode.new(tag.position, color, {}), startIndex + 1, {}, {})
end

local function toHexColor(color)
   local isHexColor = color:match("^#[0-9a-fA-F]*$") ~= nil and #color == 7

   if not isHexColor then
      return nil
   end

   local hexColorWithoutTheHash = color:sub(2, #color)
   return hexColorWithoutTheHash
end

local function parseOpenHexColorTag(tag, startIndex)
   local hexColor = toHexColor(tag.name)

   if not hexColor then
      return common.ParseReject.new()
   end

   if #tag.arguments > 0 then
      return common.ParseFail.new(common.Problem.new("too many argument in hex color tag", tag.position))
   end

   return common.ParseAccept.new(parsetree.HexColorNode.new(tag.position, hexColor, {}), startIndex + 1, {}, {})
end

local function parseOpenColorTag(tag, startIndex)
   local isColorTag = tag.name == "color"

   if not isColorTag then
      return common.ParseReject.new()
   end

   local colorArg = tag.arguments[1]

   if not colorArg then
      return common.ParseFail.new(common.Problem.new("not enough argument in color tag", tag.position))
   end

   local namedColor = toNamedColor(colorArg.content)
   local hexColor = toHexColor(colorArg.content)

   if not (namedColor or hexColor) then
      return common.ParseFail.new(common.Problem.new("invalid color name " .. colorArg.content .. " in color tag", tag.position))
   end

   if #tag.arguments > 1 then
      return common.ParseFail.new(common.Problem.new("too many argument in color tag", tag.position))
   end

   if namedColor then
      return common.ParseAccept.new(parsetree.NamedColorNode.new(tag.position, namedColor, {}), startIndex + 1, {}, {})
   else
      return common.ParseAccept.new(parsetree.HexColorNode.new(tag.position, hexColor, {}), startIndex + 1, {}, {})
   end
end

local function parseOpenDecorationTag(tag, startIndex)
   local validDecorations = {
      bold = "bold",
      b = "bold",
      italic = "italic",
      i = "italic",
      underlined = "underlined",
      u = "underlined",
      strikethrough = "strikethrough",
      st = "strikethrough",
      obfuscated = "obfuscated",
      obf = "obfuscated",
   }

   local decoration = validDecorations[tag.name]

   if not decoration then
      return common.ParseReject.new()
   end

   if #tag.arguments > 0 then
      return common.ParseFail.new(common.Problem.new("too many argument in " .. decoration .. " tag", tag.position))
   end

   return common.ParseAccept.new(parsetree.DecorationNode.new(tag.position, decoration, {}), startIndex + 1, {}, {})
end

local function parseOpenHoverTag(tag, startIndex)
   local isHoverTag = tag.name == "hover"

   if not isHoverTag then
      return common.ParseReject.new()
   end

   local actionArg = tag.arguments[1]

   if not actionArg then
      return common.ParseFail.new(common.Problem.new("not enough argument for hover tag", tag.position))
   end

   if actionArg.content == "show_text" then
      local textArg = tag.arguments[2]

      if not textArg then
         return common.ParseFail.new(common.Problem.new("not enough argument for hover:show_text tag", tag.position))
      end
      if #tag.arguments > 2 then
         return common.ParseFail.new(common.Problem.new("too many argument for hover:show_text tag", tag.position))
      end

      local secondaryTokenizeResult = lexer.tokenize(textArg.content)

      local warnings = secondaryTokenizeResult.warnings
      local strictProblems = secondaryTokenizeResult.strictProblems

      local secondaryParseResult = parser.parse(secondaryTokenizeResult.result)

      local childNodes = secondaryParseResult.result

      for _, warning in ipairs(secondaryParseResult.warnings) do
         warnings[#warnings + 1] = warning
      end

      for _, strictProblem in ipairs(secondaryParseResult.strictProblems) do
         strictProblems[#strictProblems + 1] = strictProblem
      end

      positionTranslator.convertPositions(childNodes, warnings, strictProblems, textArg.position, textArg.originalString)

      return common.ParseAccept.new(parsetree.ShowTextNode.new(tag.position, childNodes, {}), startIndex + 1, warnings, strictProblems)
   end

   return common.ParseFail.new(common.Problem.new("invalid hover tag action", tag.position))
end











local UnhandledTag = {}





function UnhandledTag.new(tagToken)
   local self = setmetatable({}, { __index = UnhandledTag })
   self.tagToken = tagToken
   self.isEndTag = false
   self.isResetTag = false
   if tagToken.name == "reset" then
      self.isResetTag = true
      return self
   end
   assert(tagToken.isEndTag == true)
   self.isEndTag = true
   return self
end

local function someoneCanConsumeEndTag(openedTags, closeTag)
   for i = #openedTags, 1, -1 do
      if tagMatches(openedTags[i], closeTag) then
         return true
      end
   end
   return false
end

local parseNormalTag
local parseComponentsUntilCloseOrReset

function parseNormalTag(tokens, openedTags, startIndex)
   local startTag = tokens[startIndex]
   local isStartTag = startTag.kind == "TagToken" and not startTag.isEndTag

   if not isStartTag then
      return common.ParseReject.new()
   end

   local warnings = {}
   local strictProblems = {}

   local function addWarningsAndProblems(result)
      for _, warning in ipairs(result.warnings) do
         warnings[#warnings + 1] = warning
      end
      for _, problem in ipairs(result.strictProblems) do
         strictProblems[#strictProblems + 1] = problem
      end
   end

   assert(startTag.kind == "TagToken")

   local tagParsersToTry = { parseOpenNamedColorTag, parseOpenHexColorTag, parseOpenColorTag, parseOpenDecorationTag, parseOpenHoverTag }

   local foundNode = nil

   for _, tagParser in ipairs(tagParsersToTry) do
      local tagResult = tagParser(startTag, startIndex)
      if tagResult.kind == "ParseAccept" then
         foundNode = tagResult.result
         addWarningsAndProblems(tagResult)
         break
      elseif tagResult.kind == "ParseFail" then
         return tagResult
      end

   end

   if foundNode == nil then
      return common.ParseReject.new()
   end
   local resultNode = foundNode

   openedTags[#openedTags + 1] = startTag

   local result = parseComponentsUntilCloseOrReset(tokens, openedTags, startIndex + 1)
   addWarningsAndProblems(result)

   local unhandledTag = result.result.unhandledTag
   local toPropagateTag = false
   if unhandledTag == nil then

      strictProblems[#strictProblems + 1] = common.Problem.new("tag " .. startTag.name .. " does not have an end tag", startTag.position)
      toPropagateTag = false

   elseif unhandledTag.isEndTag then
      assert(startTag.kind == "TagToken")
      if tagMatches(startTag, unhandledTag.tagToken) then

         toPropagateTag = false
      else

         strictProblems[#strictProblems + 1] = common.Problem.new("tag " .. startTag.name .. " does not have an end tag", startTag.position)
         toPropagateTag = true
      end

   else
      assert(unhandledTag.isResetTag)

      toPropagateTag = true
   end

   openedTags[#openedTags] = nil
   resultNode.components = result.result.components
   return common.ParseAccept.new({ node = resultNode, unhandledTag = toPropagateTag and unhandledTag or nil }, result.nextIndex, warnings, strictProblems)
end

function parseComponentsUntilCloseOrReset(tokens, openedTags, startIndex)
   local components = {}
   local warnings = {}
   local strictProblems = {}

   local function addWarningsAndProblems(result)
      for _, warning in ipairs(result.warnings) do
         warnings[#warnings + 1] = warning
      end
      for _, problem in ipairs(result.strictProblems) do
         strictProblems[#strictProblems + 1] = problem
      end
   end

   local index = startIndex
   while index <= #tokens do
      local moveOn = false
      local token = tokens[index]

      local function acceptComponentAndMoveOn(component, nextIndex)
         components[#components + 1] = component
         moveOn = true
         index = nextIndex
      end

      if not moveOn and token.kind == "PlainTextToken" then
         acceptComponentAndMoveOn(parsetree.PlainTextNode.new(token.position, token.content), index + 1)
      end

      if not moveOn and token.kind == "NewlineToken" then
         acceptComponentAndMoveOn(parsetree.NewlineNode.new(token.position), index + 1)
      end

      if not moveOn and token.kind == "TagToken" and token.isEndTag then
         local closeTagIsValid = someoneCanConsumeEndTag(openedTags, token)

         if closeTagIsValid then
            local toConsumeEndTagNow = 1
            return common.ParseAccept.new({ components = components, unhandledTag = UnhandledTag.new(token) }, index + toConsumeEndTagNow, warnings, strictProblems)

         else

            warnings[#warnings + 1] = common.Problem.new("invalid end tag " .. token.name, token.position)
            acceptComponentAndMoveOn(parsetree.PlainTextNode.new(token.position, token.originalString), index + 1)
         end
      end

      if not moveOn and token.kind == "TagToken" then
         local resetTagResult = parseResetTag(token, index)

         if resetTagResult.kind == "ParseAccept" then
            assert(token.name == "reset")
            addWarningsAndProblems(resetTagResult)
            local toConsumeResetTagNow = 1
            return common.ParseAccept.new({ components = components, unhandledTag = UnhandledTag.new(token) }, index + toConsumeResetTagNow, warnings, strictProblems)

         elseif resetTagResult.kind == "ParseFail" then

            warnings[#warnings + 1] = resetTagResult.failure
            acceptComponentAndMoveOn(parsetree.PlainTextNode.new(token.position, token.originalString), index + 1)

         else
            assert(resetTagResult.kind == "ParseReject")
         end
      end

      if not moveOn and token.kind == "TagToken" then
         local voidTagResult = parseVoidTag(token, index)

         if voidTagResult.kind == "ParseAccept" then
            addWarningsAndProblems(voidTagResult)
            acceptComponentAndMoveOn(voidTagResult.result, voidTagResult.nextIndex)

         elseif voidTagResult.kind == "ParseFail" then

            warnings[#warnings + 1] = voidTagResult.failure
            acceptComponentAndMoveOn(parsetree.PlainTextNode.new(token.position, token.originalString), index + 1)

         else
            assert(voidTagResult.kind == "ParseReject")
         end
      end

      if not moveOn and token.kind == "TagToken" then
         local normalTagResult = parseNormalTag(tokens, openedTags, index)

         if normalTagResult.kind == "ParseAccept" then
            addWarningsAndProblems(normalTagResult)
            acceptComponentAndMoveOn(normalTagResult.result.node, normalTagResult.nextIndex)

            local unhandledTag = normalTagResult.result.unhandledTag
            local hasPropagatedUnhandledTag = unhandledTag ~= nil
            if hasPropagatedUnhandledTag then
               return common.ParseAccept.new({ components = components, unhandledTag = unhandledTag }, normalTagResult.nextIndex, warnings, strictProblems)
            end

         elseif normalTagResult.kind == "ParseFail" then

            warnings[#warnings + 1] = normalTagResult.failure
            acceptComponentAndMoveOn(parsetree.PlainTextNode.new(token.position, token.originalString), index + 1)

         else
            assert(normalTagResult.kind == "ParseReject")
         end
      end

      if not moveOn then
         assert(token.kind == "TagToken")

         warnings[#warnings + 1] = common.Problem.new("unknown tag " .. token.name, token.position)
         acceptComponentAndMoveOn(parsetree.PlainTextNode.new(token.position, token.originalString), index + 1)
      end
   end


   return common.ParseAccept.new({ components = components, unhandledTag = nil }, index, warnings, strictProblems)
end

function parser.parse(tokens)
   local components = {}
   local openedTags = {}
   local index = 1
   local warnings = {}
   local strictProblems = {}

   local function addWarningsAndProblems(result)
      for _, warning in ipairs(result.warnings) do
         warnings[#warnings + 1] = warning
      end
      for _, problem in ipairs(result.strictProblems) do
         strictProblems[#strictProblems + 1] = problem
      end
   end

   if #tokens < 1 then
      return common.ParseAccept.new(parsetree.MinecraftTextNode.new(common.Position.new(1, 1, 1), components), index, warnings, strictProblems)
   end

   while index <= #tokens do
      local result = parseComponentsUntilCloseOrReset(tokens, openedTags, index)
      addWarningsAndProblems(result)

      for _, newComponent in ipairs(result.result.components) do
         components[#components + 1] = newComponent
      end

      local unhandledTag = result.result.unhandledTag

      if unhandledTag == nil then


      elseif unhandledTag.isEndTag then

         components[#components + 1] = parsetree.PlainTextNode.new(unhandledTag.tagToken.position, unhandledTag.tagToken.originalString)

      else
         assert(unhandledTag.isResetTag)

      end

      index = result.nextIndex
   end

   return common.ParseAccept.new(parsetree.MinecraftTextNode.new(tokens[1].position, components), index, warnings, strictProblems)
end

return parser
