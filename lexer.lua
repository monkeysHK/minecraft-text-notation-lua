local common = require("common")

local lexer = { PlainTextToken = {}, NewlineToken = {}, TagToken = {}, TagSegment = {} }


































function lexer.PlainTextToken.new(position, content)
   local self = setmetatable({}, { __index = lexer.PlainTextToken })
   self.kind = "PlainTextToken"
   self.position = position
   self.content = content
   return self
end

function lexer.NewlineToken.new(position)
   local self = setmetatable({}, { __index = lexer.NewlineToken })
   self.kind = "NewlineToken"
   self.position = position
   return self
end

function lexer.TagToken.new(position, name, arguments, isEndTag, originalString)
   local self = setmetatable({}, { __index = lexer.TagToken })
   self.kind = "TagToken"
   self.position = position
   self.name = name
   self.arguments = arguments
   self.isEndTag = isEndTag
   self.originalString = originalString
   return self
end

function lexer.TagSegment.new(position, content, originalString)
   local self = setmetatable({}, { __index = lexer.TagSegment })
   self.position = position
   self.content = content
   self.originalString = originalString
   return self
end

local function acceptForLexer(result, nextIndex, warnings)
   local emptyStrictProblems = {}
   return common.ParseAccept.new(result, nextIndex, warnings, emptyStrictProblems)
end


local StringReference = {}





function StringReference.new(text)
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

   local self = setmetatable({}, { __index = StringReference })
   self.text = text
   self.length = #text
   self.positionMap = precomputePositionMap(text, #text)
   return self
end

function StringReference:getPosition(index)
   local position = self.positionMap[index]
   assert(position ~= nil)
   return position
end

local function tokenizeNonEmptyStringWithValidator(
   textref,
   startIndex,
   validEscapes,
   readUntilChars,
   validateChar,
   validateFailMessage)

   local pos = startIndex
   local content = ""
   local warnings = {}

   while pos <= textref.length do
      local ch = textref.text:sub(pos, pos)

      local reachedTheEnd = readUntilChars[ch]
      if reachedTheEnd then
         break
      end

      if not validateChar(ch) then
         return common.ParseFail.new(common.Problem.new(validateFailMessage:format(ch), textref:getPosition(pos)))
      end

      local isEscape = ch == "\\"
      if isEscape then
         local escapeSequence = textref.text:sub(pos, pos + 1)

         local escapeResult = validEscapes[escapeSequence]
         if escapeResult then
            assert(#escapeResult == 1)
            content = content .. escapeResult
            pos = pos + (1 + 1)
         else

            warnings[#warnings + 1] = common.Problem.new("invalid escape " .. escapeSequence, textref:getPosition(pos))
            content = content .. "\\"
            pos = pos + 1
         end

      else
         content = content .. ch
         pos = pos + 1

      end

   end

   if content == "" then
      return common.ParseReject.new()
   end

   return acceptForLexer(content, pos, warnings)

end

local function tokenizeNonEmptyString(
   textref,
   startIndex,
   validEscapes,
   readUntilChars)

   local function anyCharValidator(_)
      return true
   end

   return tokenizeNonEmptyStringWithValidator(
   textref,
   startIndex,
   validEscapes,
   readUntilChars,
   anyCharValidator,
   "unused")

end

local function seekExpectedStrings(
   textref,
   startIndex,
   expectedStrings)

   local matches = false
   local matchedString = ""

   for _, expectedString in ipairs(expectedStrings) do
      matches = textref.text:sub(startIndex, startIndex + #expectedString - 1) == expectedString
      if matches then
         matchedString = expectedString
         break
      end
   end

   if not matches then
      return common.ParseReject.new()
   end

   local noWarning = {}
   return acceptForLexer(matchedString, startIndex + #matchedString, noWarning)
end

local function tokenizeTagName(textref, startIndex)
   local validEscapes = {}

   local readUntilChars = {
      [':'] = true,
      ['>'] = true,
   }
   local function alnumUnderscoreValidator(ch)
      return ch:match("^[0-9a-zA-Z_]*$") ~= nil
   end
   local function tagNameValidator(char)
      return alnumUnderscoreValidator(char) or char == "#"
   end

   local result = tokenizeNonEmptyStringWithValidator(
   textref,
   startIndex,
   validEscapes,
   readUntilChars,
   tagNameValidator,
   "invalid character in tag name: %s")


   if result.kind == "ParseReject" then
      return common.ParseFail.new(common.Problem.new("tag name cannot be empty", textref:getPosition(startIndex)))
   end

   return result
end

local function tokenizeUnquotedTagArg(textref, startIndex)
   local validEscapes = {}

   local readUntilChars = {
      [':'] = true,
      ['>'] = true,
   }
   local function alnumUnderscoreValidator(ch)
      return ch:match("^[0-9a-zA-Z_]*$") ~= nil
   end

   local result = tokenizeNonEmptyStringWithValidator(
   textref,
   startIndex,
   validEscapes,
   readUntilChars,
   alnumUnderscoreValidator,
   "invalid character in unquoted tag argument: %s")


   local isEmptyString = result.kind == "ParseReject"
   local acceptPosition = textref:getPosition(startIndex)

   if isEmptyString then
      local noWarning = {}
      return acceptForLexer(lexer.TagSegment.new(acceptPosition, "", ""), startIndex, noWarning)
   end

   if result.kind == "ParseFail" then
      return result
   end

   assert(result.kind == "ParseAccept")
   local originalString = textref.text:sub(startIndex, result.nextIndex - 1)

   return acceptForLexer(lexer.TagSegment.new(acceptPosition, result.result, originalString), result.nextIndex, result.warnings)
end

local function tokenizeSingleQuotedTagArg(textref, startIndex)
   local seekResult = seekExpectedStrings(textref, startIndex, { "'" })

   if seekResult.kind == "ParseReject" or seekResult.kind == "ParseFail" then
      return common.ParseReject.new()
   end

   local validEscapes = {
      ["\\'"] = "'",
      ['\\\\'] = '\\',
   }
   local readUntilChars = {
      ["'"] = true,
   }

   local result = tokenizeNonEmptyString(
   textref,
   seekResult.nextIndex,
   validEscapes,
   readUntilChars)


   if result.kind == "ParseFail" then
      return result
   end

   local isEmptyString = result.kind == "ParseReject"
   local endQuotePosition = result.kind == "ParseAccept" and result.nextIndex or startIndex + 1

   local seekResultEnd = seekExpectedStrings(textref, endQuotePosition, { "'" })

   if seekResultEnd.kind == "ParseReject" or seekResultEnd.kind == "ParseFail" then
      return common.ParseFail.new(common.Problem.new("unclosed single-quoted tag argument", textref:getPosition(endQuotePosition)))
   end

   local acceptPosition = textref:getPosition(startIndex)
   local originalString = textref.text:sub(startIndex, seekResultEnd.nextIndex - 1)

   if isEmptyString then
      local noWarning = {}
      return acceptForLexer(lexer.TagSegment.new(acceptPosition, "", originalString), seekResultEnd.nextIndex, noWarning)
   end

   assert(result.kind == "ParseAccept")
   return acceptForLexer(lexer.TagSegment.new(acceptPosition, result.result, originalString), seekResultEnd.nextIndex, result.warnings)
end

local function tokenizeDoubleQuotedTagArg(textref, startIndex)
   local seekResult = seekExpectedStrings(textref, startIndex, { '"' })

   if seekResult.kind == "ParseReject" or seekResult.kind == "ParseFail" then
      return common.ParseReject.new()
   end

   local validEscapes = {
      ['\\"'] = '"',
      ['\\\\'] = '\\',
   }
   local readUntilChars = {
      ['"'] = true,
   }

   local result = tokenizeNonEmptyString(
   textref,
   seekResult.nextIndex,
   validEscapes,
   readUntilChars)


   if result.kind == "ParseFail" then
      return result
   end

   local isEmptyString = result.kind == "ParseReject"
   local endQuotePosition = result.kind == "ParseAccept" and result.nextIndex or startIndex + 1

   local seekResultEnd = seekExpectedStrings(textref, endQuotePosition, { '"' })

   if seekResultEnd.kind == "ParseReject" or seekResultEnd.kind == "ParseFail" then
      return common.ParseFail.new(common.Problem.new("unclosed double-quoted tag argument", textref:getPosition(endQuotePosition)))
   end

   local acceptPosition = textref:getPosition(startIndex)
   local originalString = textref.text:sub(startIndex, seekResultEnd.nextIndex - 1)

   if isEmptyString then
      local noWarning = {}
      return acceptForLexer(lexer.TagSegment.new(acceptPosition, "", originalString), seekResultEnd.nextIndex, noWarning)
   end

   assert(result.kind == "ParseAccept")
   return acceptForLexer(lexer.TagSegment.new(acceptPosition, result.result, originalString), seekResultEnd.nextIndex, result.warnings)
end

local function tokenizeTag(textref, startIndex)
   local startTagResult = seekExpectedStrings(textref, startIndex, { "</", "<" })

   if startTagResult.kind == "ParseReject" or startTagResult.kind == "ParseFail" then
      return common.ParseReject.new()
   end

   local warnings = {}

   local isEndTag = startTagResult.result == "</"

   local tagNameResult = tokenizeTagName(textref, startTagResult.nextIndex)

   if tagNameResult.kind == "ParseFail" then

      warnings[#warnings + 1] = tagNameResult.failure
      return acceptForLexer(lexer.PlainTextToken.new(textref:getPosition(startIndex), textref.text:sub(startIndex, tagNameResult.failure.position.index - 1)), tagNameResult.failure.position.index, warnings)
   end

   assert(not (tagNameResult.kind == "ParseReject"))

   for _, warning in ipairs(tagNameResult.warnings) do
      warnings[#warnings + 1] = warning
   end

   local pos = tagNameResult.nextIndex
   local tokenizersToTry = { tokenizeDoubleQuotedTagArg, tokenizeSingleQuotedTagArg, tokenizeUnquotedTagArg }
   local arguments = {}

   while pos <= textref.length do
      local seekResult = seekExpectedStrings(textref, pos, { ">", ":" })
      if seekResult.kind == "ParseReject" or seekResult.kind == "ParseFail" then

         local ch = textref.text:sub(pos, pos)
         warnings[#warnings + 1] = common.Problem.new("invalid character in tag: " .. ch, textref:getPosition(pos))
         return acceptForLexer(lexer.PlainTextToken.new(textref:getPosition(startIndex), textref.text:sub(startIndex, pos - 1)), pos, warnings)
      end

      pos = seekResult.nextIndex

      local reachedEndOfTag = seekResult.result == ">"
      if reachedEndOfTag then
         local originalString = textref.text:sub(startIndex, pos - 1)
         return acceptForLexer(lexer.TagToken.new(textref:getPosition(startIndex), tagNameResult.result, arguments, isEndTag, originalString), pos, warnings)
      end

      local foundResult = nil
      for _, tokenizer in ipairs(tokenizersToTry) do
         local result = tokenizer(textref, pos)
         if result.kind == "ParseFail" then

            warnings[#warnings + 1] = result.failure
            return acceptForLexer(lexer.PlainTextToken.new(textref:getPosition(startIndex), textref.text:sub(startIndex, result.failure.position.index - 1)), result.failure.position.index, warnings)
         end

         if result.kind == "ParseAccept" then
            foundResult = result
            break
         end


      end

      assert(foundResult.kind == "ParseAccept")
      arguments[#arguments + 1] = foundResult.result
      pos = foundResult.nextIndex
      for _, warning in ipairs(foundResult.warnings) do
         warnings[#warnings + 1] = warning
      end
   end


   warnings[#warnings + 1] = common.Problem.new("unclosed tag", textref:getPosition(pos))
   return acceptForLexer(lexer.PlainTextToken.new(textref:getPosition(startIndex), textref.text:sub(startIndex, pos - 1)), pos, warnings)
end

local function tokenizeNewline(textref, startIndex)
   local result = seekExpectedStrings(textref, startIndex, { "\n" })

   if result.kind == "ParseReject" or result.kind == "ParseFail" then
      return common.ParseReject.new()
   end

   return acceptForLexer(lexer.NewlineToken.new(textref:getPosition(startIndex)), result.nextIndex, {})
end

local function tokenizePlainText(textref, startIndex)
   local validEscapes = {
      ['\\<'] = '<',
      ['\\\\'] = '\\',
   }
   local readUntilChars = {
      ['<'] = true,
      ['\n'] = true,
   }

   local result = tokenizeNonEmptyString(
   textref,
   startIndex,
   validEscapes,
   readUntilChars)


   assert(not (result.kind == "ParseFail"))

   if result.kind == "ParseAccept" then
      return acceptForLexer(lexer.PlainTextToken.new(textref:getPosition(startIndex), result.result), result.nextIndex, result.warnings)
   end

   return result
end

function lexer.tokenize(text)
   local tokens = {}
   local warnings = {}

   local textref = StringReference.new(text)

   local pos = 1

   local tokenizersInCycle = { tokenizePlainText, tokenizeNewline, tokenizeTag }

   while pos <= textref.length do
      for _, tokenizer in ipairs(tokenizersInCycle) do
         if pos > textref.length then
            break
         end

         local result = tokenizer(textref, pos)

         if result.kind == "ParseAccept" then
            tokens[#tokens + 1] = result.result
            pos = result.nextIndex
            for _, warning in ipairs(result.warnings) do
               warnings[#warnings + 1] = warning
            end
         end

         assert(not (result.kind == "ParseFail"))


      end
   end

   return acceptForLexer(tokens, pos, warnings)
end

return lexer
