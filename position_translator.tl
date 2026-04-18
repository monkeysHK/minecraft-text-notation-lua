local common = require("common")
local parsetree = require("parsetree")

local record positionTranslator
end

local type PositionMap = {common.Position}  -- A continuous sequence that maps string indices to Positions

local function precomputePositionMap(input: string, length: integer): PositionMap
    local positionMap: PositionMap = {}
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
    positionMap[length + 1] = common.Position.new(length + 1, line, col + 1)  -- eof
    return positionMap
end

local function toGlobalPositionMap(positionMap: PositionMap, parentPosition: common.Position): PositionMap
    local newPositionMap: PositionMap = {}

    for _, position in ipairs(positionMap) do
        newPositionMap[#newPositionMap + 1] = position:toGlobalPosition(parentPosition)
    end

    return newPositionMap
end

local function computeUnescapedGlobalPositionMap(
    text: string,
    globalPosition: common.Position,
    startOffset: integer,
    validEscapes: {string: string},
    readUntilChars: {string: boolean}
): {common.Position}
    -- maps indices of original string to common.Position on the original string
    local positionMap = precomputePositionMap(text, #text)
    positionMap = toGlobalPositionMap(positionMap, globalPosition)

    -- maps indices of result string to common.Position on the original string
    local unescapedGlobalPositionMap: PositionMap = {}

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
                -- non-strict mode: invalid backslash as literal
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

local function getUnescapedGlobalPositionMapForUnquoted(text: string, parentPosition: common.Position): PositionMap
    local validEscapes: {string: string} = {
    }
    local readUntilChars: {string: boolean} = {
        [':'] = true,
        ['>'] = true,
    }

    local result = computeUnescapedGlobalPositionMap(
        text,
        parentPosition,
        0,
        validEscapes,
        readUntilChars
    )

    return result
end

local function getUnescapedGlobalPositionMapForSingleQuoted(text: string, parentPosition: common.Position): PositionMap
    assert(text:sub(1, 1) == "'")
    assert(text:sub(#text, #text) == "'")

    local validEscapes: {string: string} = {
        ["\\'"] = "'",
        ['\\\\'] = '\\',
    }
    local readUntilChars: {string: boolean} = {
        ["'"] = true,
    }

    local result = computeUnescapedGlobalPositionMap(
        text,
        parentPosition,
        1,
        validEscapes,
        readUntilChars
    )

    return result
end

local function getUnescapedGlobalPositionMapForDoubleQuoted(text: string, parentPosition: common.Position): PositionMap
    assert(text:sub(1, 1) == '"')
    assert(text:sub(#text, #text) == '"')

    local validEscapes: {string: string} = {
        ['\\"'] = '"',
        ['\\\\'] = '\\',
    }
    local readUntilChars: {string: boolean} = {
        ['"'] = true,
    }

    local result = computeUnescapedGlobalPositionMap(
        text,
        parentPosition,
        1,
        validEscapes,
        readUntilChars
    )

    return result
end

local function getUnescapedGlobalPositionMapForTagArg(text: string, parentPosition: common.Position): PositionMap
    local firstChar = text:sub(1, 1)
    if firstChar == '"' then
        return getUnescapedGlobalPositionMapForDoubleQuoted(text, parentPosition)
    end
    if firstChar == "'" then
        return getUnescapedGlobalPositionMapForSingleQuoted(text, parentPosition)
    end
    return getUnescapedGlobalPositionMapForUnquoted(text, parentPosition)
end

local function convertNodePositions(node: parsetree.Node, unescapedGlobalPositionMap: PositionMap)
    local function convertComponents(components: {parsetree.Node})
        for _, component in ipairs(components) do
            convertNodePositions(component, unescapedGlobalPositionMap)
        end
    end

    local indexIsOutOfString = node.position.index > #unescapedGlobalPositionMap
    assert(not indexIsOutOfString)
    node.position = unescapedGlobalPositionMap[node.position.index]

    if node is parsetree.MinecraftTextNode then
        convertComponents(node.components)

    elseif node is parsetree.PlainTextNode then
        -- do nothing

    elseif node is parsetree.NewlineNode then
        -- do nothing

    elseif node is parsetree.NamedColorNode then
        convertComponents(node.components)

    elseif node is parsetree.HexColorNode then
        convertComponents(node.components)

    elseif node is parsetree.DecorationNode then
        convertComponents(node.components)

    elseif node is parsetree.ShowTextNode then
        convertComponents(node.components)
        convertNodePositions(node.tooltip, unescapedGlobalPositionMap)

    else
        error("This should not be reached")
    end
end

local function convertProblemPositions(problems: {common.Problem}, unescapedGlobalPositionMap: PositionMap)
    for i, problem in ipairs(problems) do
        local newPosition = unescapedGlobalPositionMap[problem.position.index]
        problems[i].position = newPosition
    end
end

function positionTranslator.convertPositions(node: parsetree.Node, warnings: {common.Problem}, strictProblems: {common.Problem}, parentPosition: common.Position, originalTagArgString: string)
    local unescapedGlobalPositionMap = getUnescapedGlobalPositionMapForTagArg(originalTagArgString, parentPosition)

    convertNodePositions(node, unescapedGlobalPositionMap)

    convertProblemPositions(warnings, unescapedGlobalPositionMap)

    convertProblemPositions(strictProblems, unescapedGlobalPositionMap)
end

return positionTranslator

