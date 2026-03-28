local lexer = require("lexer")
local parser = require("parser")

local codegen = {}


























function codegen.makeAccept(result, warnings)
   return { kind = "CompileAccept", result = result, warnings = warnings }
end

function codegen.makeFail(errors)
   return { kind = "CompileFail", errors = errors }
end

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

local function computeReverseMap(
   text,
   startIndex,
   validEscapes,
   readUntilChars)

   local positionMap = precomputePositionMap(text, #text)
   local reverseMap = {}

   local pos = startIndex
   local content = ""

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
            reverseMap[#content + 1] = positionMap[pos]
            content = content .. escapeResult
            pos = pos + 2
         else

            reverseMap[#content + 1] = positionMap[pos]
            content = content .. "\\"
            pos = pos + 1
         end

      else
         reverseMap[#content + 1] = positionMap[pos]
         content = content .. ch
         pos = pos + 1

      end

   end

   return reverseMap

end

local function reverseUnquotedTagArg(text)
   local validEscapes = {}

   local readUntilChars = {
      [':'] = true,
      ['>'] = true,
   }

   local result = computeReverseMap(
   text,
   1,
   validEscapes,
   readUntilChars)


   return result
end

local function reverseSingleQuotedTagArg(text)
   assert(text:sub(1, 1) == "'")
   assert(text:sub(#text, #text) == "'")

   local validEscapes = {
      ["\\'"] = "'",
      ['\\\\'] = '\\',
   }
   local readUntilChars = {
      ["'"] = true,
   }

   local result = computeReverseMap(
   text,
   2,
   validEscapes,
   readUntilChars)


   return result
end

local function reverseDoubleQuotedTagArg(text)
   assert(text:sub(1, 1) == '"')
   assert(text:sub(#text, #text) == '"')

   local validEscapes = {
      ['\\"'] = '"',
      ['\\\\'] = '\\',
   }
   local readUntilChars = {
      ['"'] = true,
   }

   local result = computeReverseMap(
   text,
   2,
   validEscapes,
   readUntilChars)


   return result
end

local function reverseTagArg(text)
   local firstChar = text:sub(1, 1)
   if firstChar == '"' then
      return reverseDoubleQuotedTagArg(text)
   end
   if firstChar == "'" then
      return reverseSingleQuotedTagArg(text)
   end
   return reverseUnquotedTagArg(text)
end

local function localToGlobalPosition(localPosition, parentPosition)
   local index = parentPosition.index + localPosition.index - 1
   local line = parentPosition.line + localPosition.line - 1
   local col = localPosition.line == 1 and (parentPosition.col + localPosition.col - 1) or localPosition.col
   return lexer.makePosition(index, line, col)
end

local function translateProblemsToGlobalPositions(problems, parentPosition, originalMinecraftTextString)
   local newProblems = {}
   local reverseMap = reverseTagArg(originalMinecraftTextString)
   for _, problem in ipairs(problems) do
      newProblems[#newProblems + 1] = lexer.makeProblem(problem.message, localToGlobalPosition(reverseMap[problem.position.index], parentPosition))
   end
   return newProblems
end







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

local function genComponents(components, options)
   local result = ""
   local warnings = {}

   local function addWarnings(newWarnings)
      for _, warning in ipairs(newWarnings) do
         warnings[#warnings + 1] = warning
      end
   end

   for _, component in ipairs(components) do
      local generateResult = codegen.generate(component, options)

      if generateResult.kind == "CompileFail" then
         return generateResult
      end
      addWarnings(generateResult.warnings)

      result = result .. generateResult.result
   end

   return codegen.makeAccept(result, warnings)
end

function codegen.generate(node, options)
   local result = ""
   local warnings = {}

   local function addWarnings(newWarnings)
      for _, warning in ipairs(newWarnings) do
         warnings[#warnings + 1] = warning
      end
   end

   if node.kind == "MinecraftTextNode" then
      local componentResult = genComponents(node.components, options)
      if componentResult.kind == "CompileFail" then
         return componentResult
      end
      addWarnings(componentResult.warnings)
      result = result .. componentResult.result


   elseif node.kind == "PlainTextNode" then
      result = result .. node.content

   elseif node.kind == "NewlineNode" then
      result = result .. "<br>"

   elseif node.kind == "NamedColorNode" then
      local componentResult = genComponents(node.components, options)
      if componentResult.kind == "CompileFail" then
         return componentResult
      end
      addWarnings(componentResult.warnings)

      result = result .. span(componentResult.result, { format = node.color })

   elseif node.kind == "HexColorNode" then
      local componentResult = genComponents(node.components, options)
      if componentResult.kind == "CompileFail" then
         return componentResult
      end
      addWarnings(componentResult.warnings)

      result = result .. span(componentResult.result, { style = "color: #" .. node.color .. ";" })

   elseif node.kind == "DecorationNode" then
      local componentResult = genComponents(node.components, options)
      if componentResult.kind == "CompileFail" then
         return componentResult
      end
      addWarnings(componentResult.warnings)

      result = result .. span(componentResult.result, { format = node.decoration })

   elseif node.kind == "ShowTextNode" then
      local showTextSecondaryParse = codegen.compile(node.text, options)
      if showTextSecondaryParse.kind == "CompileFail" then
         return codegen.makeFail(translateProblemsToGlobalPositions(showTextSecondaryParse.errors, node.textPosition, node.originalString))
      end
      addWarnings(translateProblemsToGlobalPositions(showTextSecondaryParse.warnings, node.textPosition, node.originalString))

      local mctooltip = span(showTextSecondaryParse.result, { class = "mctooltip" })

      local componentResult = genComponents(node.components, options)
      if componentResult.kind == "CompileFail" then
         return componentResult
      end
      addWarnings(componentResult.warnings)

      result = result .. span(componentResult.result .. mctooltip, {})

   else
      error("This should not be reached")
   end

   return codegen.makeAccept(result, warnings)
end

function codegen.compile(text, options)
   local warnings = {}

   local function addWarnings(newWarnings)
      for _, warning in ipairs(newWarnings) do
         warnings[#warnings + 1] = warning
      end
   end

   local function addWarningsAsErrors(newErrors, newWarnings)
      for _, warning in ipairs(newWarnings) do
         newErrors[#newErrors + 1] = warning
      end
   end

   local tokens = lexer.tokenize(text)

   if options.useStrictMode then
      local hasWarning = #tokens.warnings > 0
      if hasWarning then
         return codegen.makeFail(tokens.warnings)
      end
   end

   addWarnings(tokens.warnings)

   local ast = parser.parse(tokens.result)

   if options.useStrictMode then
      local hasErrorOrWarning = #ast.strictProblems > 0 or #ast.warnings > 0
      if hasErrorOrWarning then
         local errors = ast.strictProblems
         addWarningsAsErrors(errors, ast.warnings)
         return codegen.makeFail(errors)
      end
   end

   addWarnings(ast.warnings)

   local result = codegen.generate(ast.result, options)

   if result.kind == "CompileFail" then
      return result
   end

   addWarnings(result.warnings)

   return codegen.makeAccept(result.result, warnings)
end

return codegen
