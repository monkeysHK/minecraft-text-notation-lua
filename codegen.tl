local lexer = require("lexer")
local parser = require("parser")

local record codegen

    type CompileResult = CompileAccept | CompileFail

    record CompileAccept
        where self.kind == "CompileAccept"

        kind: string
        result: string
        warnings: {lexer.Problem}
    end

    record CompileFail
        where self.kind == "CompileFail"

        kind: string
        errors: {lexer.Problem}
    end

    record CompileOptions
        useStrictMode: boolean | nil  -- default false
    end

    generate: function(node: parser.Node, options: CompileOptions): CompileResult
    compile: function(text: string, options: CompileOptions): CompileResult
end

function codegen.CompileAccept.new(result: string, warnings: {lexer.Problem}): codegen.CompileAccept
    local self: codegen.CompileAccept = setmetatable({}, { __index = codegen.CompileAccept })
    self.kind = "CompileAccept"
    self.result = result
    self.warnings = warnings
    return self
end

function codegen.CompileFail.new(errors: {lexer.Problem}): codegen.CompileFail
    local self: codegen.CompileFail = setmetatable({}, { __index = codegen.CompileFail })
    self.kind = "CompileFail"
    self.errors = errors
    return self
end

function codegen.CompileOptions.new(useStrictMode: boolean | nil): codegen.CompileOptions
    local self: codegen.CompileOptions = setmetatable({}, { __index = codegen.CompileOptions })
    self.useStrictMode = useStrictMode
    return self
end

local function precomputePositionMap(input: string, length: integer): {integer: lexer.Position}
    local positionMap: {integer: lexer.Position} = {}
    local line = 1
    local col = 0
    for i = 1, length do
        col = col + 1
        positionMap[i] = lexer.Position.new(i, line, col)
        local ch = input:sub(i, i)
        if ch == "\n" then
            line = line + 1
            col = 0
        end
    end
    positionMap[length + 1] = lexer.Position.new(length + 1, line, col + 1)  -- eof
    return positionMap
end

local function computeReverseMap(
    text: string,
    startIndex: integer,
    validEscapes: {string: string},
    readUntilChars: {string: boolean}
): {lexer.Position}
    local positionMap = precomputePositionMap(text, #text)  -- maps indices of original string to lexer.Position on the original string
    local reverseMap: {integer: lexer.Position} = {}  -- maps indices of result string to lexer.Position on the original string

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
                -- non-strict mode: invalid backslash as literal
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

local function reverseUnquotedTagArg(text: string): {integer: lexer.Position}
    local validEscapes: {string: string} = {
    }
    local readUntilChars: {string: boolean} = {
        [':'] = true,
        ['>'] = true,
    }

    local result = computeReverseMap(
        text,
        1,
        validEscapes,
        readUntilChars
    )

    return result
end

local function reverseSingleQuotedTagArg(text: string): {integer: lexer.Position}
    assert(text:sub(1, 1) == "'")
    assert(text:sub(#text, #text) == "'")

    local validEscapes: {string: string} = {
        ["\\'"] = "'",
        ['\\\\'] = '\\',
    }
    local readUntilChars: {string: boolean} = {
        ["'"] = true,
    }

    local result = computeReverseMap(
        text,
        2,
        validEscapes,
        readUntilChars
    )

    return result
end

local function reverseDoubleQuotedTagArg(text: string): {integer: lexer.Position}
    assert(text:sub(1, 1) == '"')
    assert(text:sub(#text, #text) == '"')

    local validEscapes: {string: string} = {
        ['\\"'] = '"',
        ['\\\\'] = '\\',
    }
    local readUntilChars: {string: boolean} = {
        ['"'] = true,
    }

    local result = computeReverseMap(
        text,
        2,
        validEscapes,
        readUntilChars
    )

    return result
end

local function reverseTagArg(text: string): {integer: lexer.Position}
    local firstChar = text:sub(1, 1)
    if firstChar == '"' then
        return reverseDoubleQuotedTagArg(text)
    end
    if firstChar == "'" then
        return reverseSingleQuotedTagArg(text)
    end
    return reverseUnquotedTagArg(text)
end

local function localToGlobalPosition(localPosition: lexer.Position, parentPosition: lexer.Position): lexer.Position
    local index = parentPosition.index + localPosition.index - 1
    local line = parentPosition.line + localPosition.line - 1
    local col = localPosition.line == 1 and (parentPosition.col + localPosition.col - 1) or localPosition.col
    return lexer.Position.new(index, line, col)
end

local function translateProblemsToGlobalPositions(problems: {lexer.Problem}, parentPosition: lexer.Position, originalMinecraftTextString: string): {lexer.Problem}
    local newProblems = {}
    local reverseMap = reverseTagArg(originalMinecraftTextString)
    for _, problem in ipairs(problems) do
        newProblems[#newProblems + 1] = lexer.Problem.new(problem.message, localToGlobalPosition(reverseMap[problem.position.index], parentPosition))
    end
    return newProblems
end

local interface HtmlOptions
    format: string | nil
    class: string | nil
    style: string | nil
end

local function span(content: string, opt: HtmlOptions): string
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

local function genComponents(components: {parser.TextComponent}, options: codegen.CompileOptions): codegen.CompileResult
    local result: string = ""
    local warnings: {lexer.Problem} = {}

    local function addWarnings(newWarnings: {lexer.Problem})
        for _, warning in ipairs(newWarnings) do
            warnings[#warnings + 1] = warning
        end
    end

    for _, component in ipairs(components) do
        local generateResult = codegen.generate(component, options)

        if generateResult is codegen.CompileFail then
            return generateResult
        end
        addWarnings(generateResult.warnings)

        result = result .. generateResult.result
    end

    return codegen.CompileAccept.new(result, warnings)
end

function codegen.generate(node: parser.Node, options: codegen.CompileOptions): codegen.CompileResult
    local result: string = ""
    local warnings: {lexer.Problem} = {}

    local function addWarnings(newWarnings: {lexer.Problem})
        for _, warning in ipairs(newWarnings) do
            warnings[#warnings + 1] = warning
        end
    end

    if node is parser.MinecraftTextNode then
        local componentResult = genComponents(node.components, options)
        if componentResult is codegen.CompileFail then
            return componentResult
        end
        addWarnings(componentResult.warnings)
        result = result .. componentResult.result


    elseif node is parser.PlainTextNode then
        result = result .. node.content

    elseif node is parser.NewlineNode then
        result = result .. "<br>"

    elseif node is parser.NamedColorNode then
        local componentResult = genComponents(node.components, options)
        if componentResult is codegen.CompileFail then
            return componentResult
        end
        addWarnings(componentResult.warnings)

        result = result .. span(componentResult.result, { format = node.color })

    elseif node is parser.HexColorNode then
        local componentResult = genComponents(node.components, options)
        if componentResult is codegen.CompileFail then
            return componentResult
        end
        addWarnings(componentResult.warnings)

        result = result .. span(componentResult.result, { style = "color: #" .. node.color .. ";" })

    elseif node is parser.DecorationNode then
        local componentResult = genComponents(node.components, options)
        if componentResult is codegen.CompileFail then
            return componentResult
        end
        addWarnings(componentResult.warnings)

        result = result .. span(componentResult.result, { format = node.decoration })

    elseif node is parser.ShowTextNode then
        local showTextSecondaryParse = codegen.compile(node.text, options)
        if showTextSecondaryParse is codegen.CompileFail then
            return codegen.CompileFail.new(translateProblemsToGlobalPositions(showTextSecondaryParse.errors, node.textPosition, node.originalString))
        end
        addWarnings(translateProblemsToGlobalPositions(showTextSecondaryParse.warnings, node.textPosition, node.originalString))

        local mctooltip = span(showTextSecondaryParse.result, { class = "mctooltip" })

        local componentResult = genComponents(node.components, options)
        if componentResult is codegen.CompileFail then
            return componentResult
        end
        addWarnings(componentResult.warnings)

        result = result .. span(componentResult.result .. mctooltip, {})

    else
        error("This should not be reached")
    end

    return codegen.CompileAccept.new(result, warnings)
end

function codegen.compile(text: string, options: codegen.CompileOptions): codegen.CompileResult
    local warnings: {lexer.Problem} = {}

    local function addWarnings(newWarnings: {lexer.Problem})
        for _, warning in ipairs(newWarnings) do
            warnings[#warnings + 1] = warning
        end
    end

    local function addWarningsAsErrors(newErrors: {lexer.Problem}, newWarnings: {lexer.Problem})
        for _, warning in ipairs(newWarnings) do
            newErrors[#newErrors + 1] = warning
        end
    end

    local tokens = lexer.tokenize(text)

    if options.useStrictMode then
        local hasWarning = #tokens.warnings > 0
        if hasWarning then
            return codegen.CompileFail.new(tokens.warnings)
        end
    end

    addWarnings(tokens.warnings)

    local ast = parser.parse(tokens.result)

    if options.useStrictMode then
        local hasErrorOrWarning = #ast.strictProblems > 0 or #ast.warnings > 0
        if hasErrorOrWarning then
            local errors = ast.strictProblems
            addWarningsAsErrors(errors, ast.warnings)
            return codegen.CompileFail.new(errors)
        end
    end

    addWarnings(ast.warnings)

    local result = codegen.generate(ast.result, options)

    if result is codegen.CompileFail then
        return result
    end

    addWarnings(result.warnings)

    return codegen.CompileAccept.new(result.result, warnings)
end

return codegen

