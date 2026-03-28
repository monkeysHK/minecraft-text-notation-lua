local lexer = {}









































































function lexer.makePlainText(position, content)
   return { kind = "PlainTextToken", position = position, content = content }
end

function lexer.makeNewline(position)
   return { kind = "NewlineToken", position = position }
end

function lexer.makeTag(position, name, arguments, isEndTag, originalString)
   return { kind = "TagToken", position = position, name = name, arguments = arguments, isEndTag = isEndTag, originalString = originalString }
end

function lexer.makeTagSegment(position, content, originalString)
   return { position = position, content = content, originalString = originalString }
end

function lexer.makePosition(index, line, col)
   return { index = index, line = line, col = col }
end

function lexer.makeProblem(message, position)
   return { message = message, position = position }
end

function lexer.makeAccept(result, nextIndex, warnings)
   return { kind = "TokenizeAccept", result = result, nextIndex = nextIndex, warnings = warnings }
end

function lexer.makeReject()
   return { kind = "TokenizeReject" }
end

function lexer.makeFail(failure)
   return { kind = "TokenizeFail", failure = failure }
end








local function makeStringReference(text)
   local function precomputePositionMap(input, length)
      local positionMap = {}
      local line = 1
      local col = 0
      for i = 1, length do
         col = col + 1
         positionMap[i] = lexer.makePosition(i, line, col)
         local ch = input:sub(i, i)
         if ch == "\n" then
            line = line + 1
            col = 0
         end
      end
      positionMap[length + 1] = lexer.makePosition(length + 1, line, col + 1)
      return positionMap
   end

   return {
      text = text,
      length = #text,
      positionMap = precomputePositionMap(text, #text),
   }
end

local function makePosition(index, textref)
   local position = textref.positionMap[index]
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
         return lexer.makeFail(lexer.makeProblem(validateFailMessage:format(ch), makePosition(pos, textref)))
      end

      local isEscape = ch == "\\"
      if isEscape then
         local escapeSequence = textref.text:sub(pos, pos + 1)

         local escapeResult = validEscapes[escapeSequence]
         if escapeResult then
            content = content .. escapeResult
            pos = pos + 2
         else

            warnings[#warnings + 1] = lexer.makeProblem("invalid escape " .. escapeSequence, makePosition(pos, textref))
            content = content .. "\\"
            pos = pos + 1
         end

      else
         content = content .. ch
         pos = pos + 1

      end

   end

   if content == "" then
      return lexer.makeReject()
   end

   return lexer.makeAccept(content, pos, warnings)

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
      return lexer.makeReject()
   end

   local noWarning = {}
   return lexer.makeAccept(matchedString, startIndex + #matchedString, noWarning)
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


   if result.kind == "TokenizeReject" then
      return lexer.makeFail(lexer.makeProblem("tag name cannot be empty", makePosition(startIndex, textref)))
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


   local isEmptyString = result.kind == "TokenizeReject"
   local acceptPosition = makePosition(startIndex, textref)

   if isEmptyString then
      local noWarning = {}
      return lexer.makeAccept(lexer.makeTagSegment(acceptPosition, "", ""), startIndex, noWarning)
   end

   if result.kind == "TokenizeFail" then
      return result
   end

   assert(result.kind == "TokenizeAccept")
   local originalString = textref.text:sub(startIndex, result.nextIndex - 1)

   return lexer.makeAccept(lexer.makeTagSegment(acceptPosition, result.result, originalString), result.nextIndex, result.warnings)
end

local function tokenizeSingleQuotedTagArg(textref, startIndex)
   local seekResult = seekExpectedStrings(textref, startIndex, { "'" })

   if seekResult.kind == "TokenizeReject" or seekResult.kind == "TokenizeFail" then
      return lexer.makeReject()
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


   if result.kind == "TokenizeFail" then
      return result
   end

   local isEmptyString = result.kind == "TokenizeReject"
   local endQuotePosition = result.kind == "TokenizeAccept" and result.nextIndex or startIndex + 1

   local seekResultEnd = seekExpectedStrings(textref, endQuotePosition, { "'" })

   if seekResultEnd.kind == "TokenizeReject" or seekResultEnd.kind == "TokenizeFail" then
      return lexer.makeFail(lexer.makeProblem("unclosed single-quoted tag argument", makePosition(endQuotePosition, textref)))
   end

   local acceptPosition = makePosition(startIndex, textref)
   local originalString = textref.text:sub(startIndex, seekResultEnd.nextIndex - 1)

   if isEmptyString then
      local noWarning = {}
      return lexer.makeAccept(lexer.makeTagSegment(acceptPosition, "", originalString), seekResultEnd.nextIndex, noWarning)
   end

   assert(result.kind == "TokenizeAccept")
   return lexer.makeAccept(lexer.makeTagSegment(acceptPosition, result.result, originalString), seekResultEnd.nextIndex, result.warnings)
end

local function tokenizeDoubleQuotedTagArg(textref, startIndex)
   local seekResult = seekExpectedStrings(textref, startIndex, { '"' })

   if seekResult.kind == "TokenizeReject" or seekResult.kind == "TokenizeFail" then
      return lexer.makeReject()
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


   if result.kind == "TokenizeFail" then
      return result
   end

   local isEmptyString = result.kind == "TokenizeReject"
   local endQuotePosition = result.kind == "TokenizeAccept" and result.nextIndex or startIndex + 1

   local seekResultEnd = seekExpectedStrings(textref, endQuotePosition, { '"' })

   if seekResultEnd.kind == "TokenizeReject" or seekResultEnd.kind == "TokenizeFail" then
      return lexer.makeFail(lexer.makeProblem("unclosed double-quoted tag argument", makePosition(endQuotePosition, textref)))
   end

   local acceptPosition = makePosition(startIndex, textref)
   local originalString = textref.text:sub(startIndex, seekResultEnd.nextIndex - 1)

   if isEmptyString then
      local noWarning = {}
      return lexer.makeAccept(lexer.makeTagSegment(acceptPosition, "", originalString), seekResultEnd.nextIndex, noWarning)
   end

   assert(result.kind == "TokenizeAccept")
   return lexer.makeAccept(lexer.makeTagSegment(acceptPosition, result.result, originalString), seekResultEnd.nextIndex, result.warnings)
end

local function tokenizeTag(textref, startIndex)
   local startTagResult = seekExpectedStrings(textref, startIndex, { "</", "<" })

   if startTagResult.kind == "TokenizeReject" or startTagResult.kind == "TokenizeFail" then
      return lexer.makeReject()
   end

   local warnings = {}

   local isEndTag = startTagResult.result == "</"

   local tagNameResult = tokenizeTagName(textref, startTagResult.nextIndex)

   if tagNameResult.kind == "TokenizeFail" then

      warnings[#warnings + 1] = tagNameResult.failure
      return lexer.makeAccept(lexer.makePlainText(makePosition(startIndex, textref), textref.text:sub(startIndex, tagNameResult.failure.position.index - 1)), tagNameResult.failure.position.index, warnings)
   end

   assert(not (tagNameResult.kind == "TokenizeReject"))

   for _, warning in ipairs(tagNameResult.warnings) do
      warnings[#warnings + 1] = warning
   end

   local pos = tagNameResult.nextIndex
   local tokenizersToTry = { tokenizeDoubleQuotedTagArg, tokenizeSingleQuotedTagArg, tokenizeUnquotedTagArg }
   local arguments = {}

   while pos <= textref.length do
      local seekResult = seekExpectedStrings(textref, pos, { ">", ":" })
      if seekResult.kind == "TokenizeReject" or seekResult.kind == "TokenizeFail" then

         local ch = textref.text:sub(pos, pos)
         warnings[#warnings + 1] = lexer.makeProblem("invalid character in tag: " .. ch, makePosition(pos, textref))
         return lexer.makeAccept(lexer.makePlainText(makePosition(startIndex, textref), textref.text:sub(startIndex, pos - 1)), pos, warnings)
      end

      pos = seekResult.nextIndex

      local reachedEndOfTag = seekResult.result == ">"
      if reachedEndOfTag then
         local originalString = textref.text:sub(startIndex, pos - 1)
         return lexer.makeAccept(lexer.makeTag(makePosition(startIndex, textref), tagNameResult.result, arguments, isEndTag, originalString), pos, warnings)
      end

      local foundResult = nil
      for _, tokenizer in ipairs(tokenizersToTry) do
         local result = tokenizer(textref, pos)
         if result.kind == "TokenizeFail" then

            warnings[#warnings + 1] = result.failure
            return lexer.makeAccept(lexer.makePlainText(makePosition(startIndex, textref), textref.text:sub(startIndex, result.failure.position.index - 1)), result.failure.position.index, warnings)
         end

         if result.kind == "TokenizeAccept" then
            foundResult = result
            break
         end


      end

      assert(foundResult.kind == "TokenizeAccept")
      arguments[#arguments + 1] = foundResult.result
      pos = foundResult.nextIndex
      for _, warning in ipairs(foundResult.warnings) do
         warnings[#warnings + 1] = warning
      end
   end


   warnings[#warnings + 1] = lexer.makeProblem("unclosed tag", makePosition(pos, textref))
   return lexer.makeAccept(lexer.makePlainText(makePosition(startIndex, textref), textref.text:sub(startIndex, pos - 1)), pos, warnings)
end

local function tokenizeNewline(textref, startIndex)
   local result = seekExpectedStrings(textref, startIndex, { "\n" })

   if result.kind == "TokenizeReject" or result.kind == "TokenizeFail" then
      return lexer.makeReject()
   end

   return lexer.makeAccept(lexer.makeNewline(makePosition(startIndex, textref)), result.nextIndex, {})
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


   assert(not (result.kind == "TokenizeFail"))

   if result.kind == "TokenizeAccept" then
      return lexer.makeAccept(lexer.makePlainText(makePosition(startIndex, textref), result.result), result.nextIndex, result.warnings)
   end

   return result
end

function lexer.tokenize(text)
   local tokens = {}
   local warnings = {}

   local textref = makeStringReference(text)

   local pos = 1

   local tokenizersInCycle = { tokenizePlainText, tokenizeNewline, tokenizeTag }

   while pos <= textref.length do
      for _, tokenizer in ipairs(tokenizersInCycle) do
         if pos > textref.length then
            break
         end

         local result = tokenizer(textref, pos)

         if result.kind == "TokenizeAccept" then
            tokens[#tokens + 1] = result.result
            pos = result.nextIndex
            for _, warning in ipairs(result.warnings) do
               warnings[#warnings + 1] = warning
            end
         end

         assert(not (result.kind == "TokenizeFail"))


      end
   end

   return lexer.makeAccept(tokens, pos, warnings)
end

return lexer
