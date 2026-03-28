local lexer = require("lexer")

local record parser

    interface Node
        where self.kind

        kind: string
        position: lexer.Position
    end

    interface MinecraftTextNode
        is Node
        where self.kind == "MinecraftTextNode"

        components: {TextComponent}
    end

    type TextComponent = VoidTagNode | NormalTagNode | PlainTextNode

    type VoidTagNode = NewlineNode | NewlineNode

    interface NewlineNode
        is Node
        where self.kind == "NewlineNode"
    end

    interface NormalTagNode
        is Node
        where self.kind

        components: {TextComponent}
    end

    interface NamedColorNode
        is NormalTagNode
        where self.kind == "NamedColorNode"

        color: NamedColor
    end

    type NamedColor = enum "black" "dark_blue" "dark_green" "dark_aqua" "dark_red" "dark_purple" "gold" "gray" "dark_gray" "blue" "green" "aqua" "red" "light_purple" "yellow" "white" end

    interface HexColorNode
        is NormalTagNode
        where self.kind == "HexColorNode"

        color: string  -- 6 digit hex code without the `#` symbol
    end

    interface DecorationNode
        is NormalTagNode
        where self.kind == "DecorationNode"

        decoration: Decoration
    end

    type Decoration = enum "bold" "italic" "underlined" "strikethrough" "obfuscated" end

    type HoverNode = ShowTextNode | ShowTextNode

    interface ShowTextNode
        is NormalTagNode
        where self.kind == "ShowTextNode"

        text: string
        textPosition: lexer.Position
        originalString: string
    end

    interface PlainTextNode
        is NormalTagNode
        where self.kind == "PlainTextNode"

        content: string
    end

    type ParseResult<T> = ParseAccept<T> | ParseReject | ParseFail

    -- Used when parser successfully parses a token
    interface ParseAccept<T>
        where self.kind == "ParseAccept"

        kind: string
        result: T
        nextIndex: integer
        warnings: {lexer.Problem}  -- problems that are errors in strict mode, and should be corrected in non-strict mode
        strictProblems: {lexer.Problem}  -- problems that are errors in strict mode and are valid in non-strict mode
    end

    -- Used when parser determines that this is not the required token
    interface ParseReject
        where self.kind == "ParseReject"

        kind: string
    end

    -- Used when parser determines that this is the required token
    -- but something was wrong
    interface ParseFail
        where self.kind == "ParseFail"

        kind: string
        failure: lexer.Problem
    end

end

function parser.makeMinecraftText(position: lexer.Position, components: {parser.TextComponent}): parser.MinecraftTextNode
    return { kind = "MinecraftTextNode", position = position, components = components }
end

function parser.makeNewline(position: lexer.Position): parser.NewlineNode
    return { kind = "NewlineNode", position = position }
end

function parser.makeNamedColor(position: lexer.Position, color: parser.NamedColor, components: {parser.TextComponent}): parser.NamedColorNode
    return { kind = "NamedColorNode", position = position, color = color, components = components }
end

function parser.makeHexColor(position: lexer.Position, color: string, components: {parser.TextComponent}): parser.HexColorNode
    assert(#color == 6)
    return { kind = "HexColorNode", position = position, color = color, components = components }
end

function parser.makeDecoration(position: lexer.Position, decoration: parser.Decoration, components: {parser.TextComponent}): parser.DecorationNode
    return { kind = "DecorationNode", position = position, decoration = decoration, components = components }
end

function parser.makeShowText(position: lexer.Position, text: string, textPosition: lexer.Position, originalString: string, components: {parser.TextComponent}): parser.ShowTextNode
    return { kind = "ShowTextNode", position = position, text = text, textPosition = textPosition, originalString = originalString, components = components }
end

function parser.makePlainText(position: lexer.Position, content: string): parser.PlainTextNode
    return { kind = "PlainTextNode", position = position, content = content }
end

function parser.makeAccept<T>(result: T, nextIndex: integer, warnings: {lexer.Problem}, strictProblems: {lexer.Problem}): parser.ParseAccept<T>
    return { kind = "ParseAccept", result = result, nextIndex = nextIndex, warnings = warnings, strictProblems = strictProblems }
end

function parser.makeReject(): parser.ParseReject
    return { kind = "ParseReject" }
end

function parser.makeFail(failure: lexer.Problem): parser.ParseFail
    return { kind = "ParseFail", failure = failure }
end

local function tagMatches(startTag: lexer.TagToken, endTag: lexer.TagToken): boolean
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

local function parseNewlineTag(tag: lexer.TagToken, startIndex: integer): parser.ParseResult<parser.VoidTagNode>
    local isStartTag = tag is lexer.TagToken and not tag.isEndTag

    if not isStartTag then
        return parser.makeReject()
    end

    assert(tag is lexer.TagToken)
    if tag.name == "br" then
        if #tag.arguments > 0 then
            return parser.makeFail(lexer.makeProblem("too many argument in br tag", tag.position))
        end
        return parser.makeAccept(parser.makeNewline(tag.position), startIndex + 1, {}, {})
    end

    return parser.makeReject()
end

local function parseVoidTag(tag: lexer.TagToken, startIndex: integer): parser.ParseResult<parser.VoidTagNode>
    local tagParsersToTry = {parseNewlineTag}

    for _, tagParser in ipairs(tagParsersToTry) do
        local result = tagParser(tag, startIndex)
        if result is parser.ParseAccept<parser.VoidTagNode> or result is parser.ParseFail then
            return result
        end
    end

    return parser.makeReject()
end

local function parseResetTag(tag: lexer.TagToken, startIndex: integer): parser.ParseResult<boolean>
    local isStartTag = tag is lexer.TagToken and not tag.isEndTag

    if not isStartTag then
        return parser.makeReject()
    end

    assert(tag is lexer.TagToken)
    if tag.name == "reset" then
        if #tag.arguments > 0 then
            return parser.makeFail(lexer.makeProblem("too many argument in reset tag", tag.position))
        end
        local warnings = {}
        local strictProblems = {
            lexer.makeProblem("reset tag is not allowed", tag.position)
        }
        return parser.makeAccept(true, startIndex + 1, warnings, strictProblems)
    end

    return parser.makeReject()
end

local function toNamedColor(color: string): parser.NamedColor | nil
    local validColors: {string: parser.NamedColor} = {
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

local function parseOpenNamedColorTag(tag: lexer.TagToken, startIndex: integer): parser.ParseResult<parser.NormalTagNode>
    local color = toNamedColor(tag.name)

    if not color then
        return parser.makeReject()
    end

    assert(color is parser.NamedColor)
    if #tag.arguments > 0 then
        return parser.makeFail(lexer.makeProblem("too many argument in named color tag", tag.position))
    end

    return parser.makeAccept(parser.makeNamedColor(tag.position, color, {}), startIndex + 1, {}, {})
end

local function toHexColor(color: string): string | nil
    local isHexColor = color:match("^#[0-9a-fA-F]*$") ~= nil and #color == 7

    if not isHexColor then
        return nil
    end

    local hexColorWithoutTheHash = color:sub(2, #color)
    return hexColorWithoutTheHash
end

local function parseOpenHexColorTag(tag: lexer.TagToken, startIndex: integer): parser.ParseResult<parser.NormalTagNode>
    local hexColor = toHexColor(tag.name)

    if not hexColor then
        return parser.makeReject()
    end

    if #tag.arguments > 0 then
        return parser.makeFail(lexer.makeProblem("too many argument in hex color tag", tag.position))
    end

    return parser.makeAccept(parser.makeHexColor(tag.position, hexColor, {}), startIndex + 1, {}, {})
end

local function parseOpenColorTag(tag: lexer.TagToken, startIndex: integer): parser.ParseResult<parser.NormalTagNode>
    local isColorTag = tag.name == "color"

    if not isColorTag then
        return parser.makeReject()
    end

    local colorArg = tag.arguments[1]

    if not colorArg then
        return parser.makeFail(lexer.makeProblem("not enough argument in color tag", tag.position))
    end

    local namedColor = toNamedColor(colorArg.content)
    local hexColor = toHexColor(colorArg.content)

    if not (namedColor or hexColor) then
        return parser.makeFail(lexer.makeProblem("invalid color name " .. colorArg.content .. " in color tag", tag.position))
    end

    if #tag.arguments > 1 then
        return parser.makeFail(lexer.makeProblem("too many argument in color tag", tag.position))
    end

    if namedColor then
        return parser.makeAccept(parser.makeNamedColor(tag.position, namedColor, {}), startIndex + 1, {}, {})
    else
        return parser.makeAccept(parser.makeHexColor(tag.position, hexColor, {}), startIndex + 1, {}, {})
    end
end

local function parseOpenDecorationTag(tag: lexer.TagToken, startIndex: integer): parser.ParseResult<parser.NormalTagNode>
    local validDecorations: {string: parser.Decoration} = {
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
        return parser.makeReject()
    end

    if #tag.arguments > 0 then
        return parser.makeFail(lexer.makeProblem("too many argument in " .. decoration .. " tag", tag.position))
    end

    return parser.makeAccept(parser.makeDecoration(tag.position, decoration, {}), startIndex + 1, {}, {})
end

local function parseOpenHoverTag(tag: lexer.TagToken, startIndex: integer): parser.ParseResult<parser.NormalTagNode>
    local isHoverTag = tag.name == "hover"

    if not isHoverTag then
        return parser.makeReject()
    end

    local actionArg = tag.arguments[1]

    if not actionArg then
        return parser.makeFail(lexer.makeProblem("not enough argument for hover tag", tag.position))
    end

    if actionArg.content == "show_text" then
        local textArg = tag.arguments[2]

        if not textArg then
            return parser.makeFail(lexer.makeProblem("not enough argument for hover:show_text tag", tag.position))
        end
        if #tag.arguments > 2 then
            return parser.makeFail(lexer.makeProblem("too many argument for hover:show_text tag", tag.position))
        end

        return parser.makeAccept(parser.makeShowText(tag.position, textArg.content, textArg.position, textArg.originalString, {}), startIndex + 1, {}, {})
    end

    return parser.makeFail(lexer.makeProblem("invalid hover tag action", tag.position))
end

local interface ComponentsResult
    components: {parser.TextComponent}
    unhandledTag: UnhandledTag  -- The end tag is guaranteed to have a matching start tag in the currently opened tags
end

local interface NormalTagNodeResult
    node: parser.NormalTagNode
    unhandledTag: UnhandledTag  -- The end tag is guaranteed to have a matching start tag in the currently opened tags
end

local type UnhandledTag = EndTag | ResetTag | nil

local interface EndTag
    is lexer.TagToken
    where self.isEndTag == true
end

local interface ResetTag
    is lexer.TagToken
    where self.name == "reset"
end

local function someoneCanConsumeEndTag(openedTags: {lexer.TagToken}, closeTag: lexer.TagToken): boolean
    for i = #openedTags, 1, -1 do
        if tagMatches(openedTags[i], closeTag) then
            return true
        end
    end
    return false
end

local parseNormalTag: function ({lexer.Token}, {lexer.TagToken}, integer): parser.ParseResult<NormalTagNodeResult>
local parseComponentsUntilCloseOrReset: function({lexer.Token}, {lexer.TagToken}, integer): parser.ParseAccept<ComponentsResult>

function parseNormalTag(tokens: {lexer.Token}, openedTags: {lexer.TagToken}, startIndex: integer): parser.ParseResult<NormalTagNodeResult>
    local startTag = tokens[startIndex]
    local isStartTag = startTag is lexer.TagToken and not startTag.isEndTag

    if not isStartTag then
        return parser.makeReject()
    end

    local warnings: {lexer.Problem} = {}
    local strictProblems: {lexer.Problem} = {}

    local function addWarningsAndProblems<T>(result: parser.ParseAccept<T>)
        for _, warning in ipairs(result.warnings) do
            warnings[#warnings + 1] = warning
        end
        for _, problem in ipairs(result.strictProblems) do
            strictProblems[#strictProblems + 1] = problem
        end
    end

    assert(startTag is lexer.TagToken)

    local tagParsersToTry = { parseOpenNamedColorTag, parseOpenHexColorTag, parseOpenColorTag, parseOpenDecorationTag, parseOpenHoverTag }

    local foundNode: parser.NormalTagNode | nil = nil

    for _, tagParser in ipairs(tagParsersToTry) do
        local tagResult = tagParser(startTag, startIndex)
        if tagResult is parser.ParseAccept<parser.NormalTagNode> then
            foundNode = tagResult.result
            addWarningsAndProblems(tagResult)
            break
        elseif tagResult is parser.ParseFail then
            return tagResult
        end
        -- else continue
    end

    if foundNode == nil then
        return parser.makeReject()
    end
    local resultNode = foundNode as parser.NormalTagNode

    openedTags[#openedTags + 1] = startTag

    local result = parseComponentsUntilCloseOrReset(tokens, openedTags, startIndex + 1)
    addWarningsAndProblems(result)

    local unhandledTag = result.result.unhandledTag
    local toPropagateTag = false
    if unhandledTag == nil then
        -- non-strict mode: assume tag is closed even though it is not
        strictProblems[#strictProblems + 1] = lexer.makeProblem("tag " .. startTag.name .. " does not have an end tag", startTag.position)
        toPropagateTag = false

    elseif unhandledTag is EndTag then
        assert(startTag is lexer.TagToken)
        if tagMatches(startTag, unhandledTag) then
            -- valid
            toPropagateTag = false
        else
            -- non-strict mode: assume tag is closed and propagate unhandled tag
            strictProblems[#strictProblems + 1] = lexer.makeProblem("tag " .. startTag.name .. " does not have an end tag", startTag.position)
            toPropagateTag = true
        end

    else
        assert(unhandledTag is ResetTag)
        -- non-strict mode: end tag and propagate reset tag
        toPropagateTag = true
    end

    openedTags[#openedTags] = nil
    resultNode.components = result.result.components
    return parser.makeAccept({ node = resultNode, unhandledTag = toPropagateTag and unhandledTag or nil }, result.nextIndex, warnings, strictProblems)
end

function parseComponentsUntilCloseOrReset(tokens: {lexer.Token}, openedTags: {lexer.TagToken}, startIndex: integer): parser.ParseAccept<ComponentsResult>
    local components: {parser.TextComponent} = {}
    local warnings: {lexer.Problem} = {}
    local strictProblems: {lexer.Problem} = {}

    local function addWarningsAndProblems<T>(result: parser.ParseAccept<T>)
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

        local function acceptComponentAndMoveOn(component: parser.TextComponent, nextIndex: integer)
            components[#components + 1] = component
            moveOn = true
            index = nextIndex
        end

        if not moveOn and token is lexer.PlainTextToken then
            acceptComponentAndMoveOn(parser.makePlainText(token.position, token.content), index + 1)
        end

        if not moveOn and token is lexer.NewlineToken then
            acceptComponentAndMoveOn(parser.makeNewline(token.position), index + 1)
        end

        if not moveOn and token is lexer.TagToken and token is EndTag then
            local closeTagIsValid = someoneCanConsumeEndTag(openedTags, token)

            if closeTagIsValid then
                local toConsumeEndTagNow = 1
                return parser.makeAccept({ components = components, unhandledTag = token }, index + toConsumeEndTagNow, warnings, strictProblems)

            else
                -- non-strict mode: display as plain text even though end tag is invalid
                warnings[#warnings + 1] = lexer.makeProblem("invalid end tag " .. token.name, token.position)
                acceptComponentAndMoveOn(parser.makePlainText(token.position, token.originalString), index + 1)
            end
        end

        if not moveOn and token is lexer.TagToken then
            local resetTagResult = parseResetTag(token, index)

            if resetTagResult is parser.ParseAccept<boolean> then
                assert(token is ResetTag)
                addWarningsAndProblems(resetTagResult)
                local toConsumeResetTagNow = 1
                return parser.makeAccept({ components = components, unhandledTag = token }, index + toConsumeResetTagNow, warnings, strictProblems)

            elseif resetTagResult is parser.ParseFail then
                -- non-strict mode: display as plain text even though reset tag is invalid
                warnings[#warnings + 1] = resetTagResult.failure
                acceptComponentAndMoveOn(parser.makePlainText(token.position, token.originalString), index + 1)

            else
                assert(resetTagResult is parser.ParseReject)
            end
        end

        if not moveOn and token is lexer.TagToken then
            local voidTagResult = parseVoidTag(token, index)

            if voidTagResult is parser.ParseAccept<parser.VoidTagNode> then
                addWarningsAndProblems(voidTagResult)
                acceptComponentAndMoveOn(voidTagResult.result, voidTagResult.nextIndex)

            elseif voidTagResult is parser.ParseFail then
                -- non-strict mode: display as plain text even though void tag is invalid
                warnings[#warnings + 1] = voidTagResult.failure
                acceptComponentAndMoveOn(parser.makePlainText(token.position, token.originalString), index + 1)

            else
                assert(voidTagResult is parser.ParseReject)
            end
        end

        if not moveOn and token is lexer.TagToken then
            local normalTagResult = parseNormalTag(tokens, openedTags, index)

            if normalTagResult is parser.ParseAccept<NormalTagNodeResult> then
                addWarningsAndProblems(normalTagResult)
                acceptComponentAndMoveOn(normalTagResult.result.node, normalTagResult.nextIndex)

                local unhandledTag = normalTagResult.result.unhandledTag
                local hasPropagatedUnhandledTag = unhandledTag ~= nil
                if hasPropagatedUnhandledTag then
                    return parser.makeAccept({ components = components, unhandledTag = unhandledTag }, normalTagResult.nextIndex, warnings, strictProblems)
                end

            elseif normalTagResult is parser.ParseFail then
                -- non-strict mode: display as plain text even though normal tag is invalid
                warnings[#warnings + 1] = normalTagResult.failure
                acceptComponentAndMoveOn(parser.makePlainText(token.position, token.originalString), index + 1)

            else
                assert(normalTagResult is parser.ParseReject)
            end
        end

        if not moveOn then
            assert(token is lexer.TagToken)
            -- non-strict mode: display as plain text even though tag is invalid
            warnings[#warnings + 1] = lexer.makeProblem("unknown tag " .. token.name, token.position)
            acceptComponentAndMoveOn(parser.makePlainText(token.position, token.originalString), index + 1)
        end
    end

    -- reached end of file
    return parser.makeAccept({ components = components, unhandledTag = nil }, index, warnings, strictProblems)
end

function parser.parse(tokens: {lexer.Token}): parser.ParseAccept<parser.MinecraftTextNode>
    local components: {parser.TextComponent} = {}
    local openedTags: {lexer.TagToken} = {}
    local index = 1
    local warnings: {lexer.Problem} = {}
    local strictProblems: {lexer.Problem} = {}

    local function addWarningsAndProblems<T>(result: parser.ParseAccept<T>)
        for _, warning in ipairs(result.warnings) do
            warnings[#warnings + 1] = warning
        end
        for _, problem in ipairs(result.strictProblems) do
            strictProblems[#strictProblems + 1] = problem
        end
    end

    if #tokens < 1 then
        return parser.makeAccept(parser.makeMinecraftText(lexer.makePosition(1, 1, 1), components), index, warnings, strictProblems)
    end

    while index <= #tokens do
        local result = parseComponentsUntilCloseOrReset(tokens, openedTags, index)
        addWarningsAndProblems(result)

        for _, newComponent in ipairs(result.result.components) do
            components[#components + 1] = newComponent
        end

        local unhandledTag = result.result.unhandledTag

        if unhandledTag == nil then
            -- valid

        elseif unhandledTag is EndTag then
            -- non-strict mode: write invalid tag as plain text
            components[#components + 1] = parser.makePlainText(unhandledTag.position, unhandledTag.originalString)

        else
            assert(unhandledTag is ResetTag)
            -- valid
        end

        index = result.nextIndex
    end

    return parser.makeAccept(parser.makeMinecraftText(tokens[1].position, components), index, warnings, strictProblems)
end

return parser

