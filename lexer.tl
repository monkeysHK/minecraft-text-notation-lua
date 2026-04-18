local common = require("common")

local record lexer
    interface Token
        where self.kind

        kind: string
        position: common.Position
    end

    record PlainTextToken is Token
        where self.kind == "PlainTextToken"

        content: string
    end

    record NewlineToken is Token
        where self.kind == "NewlineToken"
    end

    record TagToken is Token
        where self.kind == "TagToken"

        name: string
        arguments: {TagSegment}
        isEndTag: boolean
        originalString: string
    end

    record TagSegment
        position: common.Position
        content: string
        originalString: string
    end

end

function lexer.PlainTextToken.new(position: common.Position, content: string): lexer.PlainTextToken
    local self: lexer.PlainTextToken = setmetatable({}, { __index = lexer.PlainTextToken })
    self.kind = "PlainTextToken"
    self.position = position
    self.content = content
    return self
end

function lexer.NewlineToken.new(position: common.Position): lexer.NewlineToken
    local self: lexer.NewlineToken = setmetatable({}, { __index = lexer.NewlineToken })
    self.kind = "NewlineToken"
    self.position = position
    return self
end

function lexer.TagToken.new(position: common.Position, name: string, arguments: {lexer.TagSegment}, isEndTag: boolean, originalString: string): lexer.TagToken
    local self: lexer.TagToken = setmetatable({}, { __index = lexer.TagToken })
    self.kind = "TagToken"
    self.position = position
    self.name = name
    self.arguments = arguments
    self.isEndTag = isEndTag
    self.originalString = originalString
    return self
end

function lexer.TagSegment.new(position: common.Position, content: string, originalString: string): lexer.TagSegment
    local self: lexer.TagSegment = setmetatable({}, { __index = lexer.TagSegment })
    self.position = position
    self.content = content
    self.originalString = originalString
    return self
end

local function acceptForLexer<T>(result: T, nextIndex: integer, warnings: {common.Problem}): common.ParseAccept<T>
    local emptyStrictProblems = {}  -- lexer does not emit strict problems
    return common.ParseAccept.new(result, nextIndex, warnings, emptyStrictProblems)
end

-- Table to pass the text without copying the text
local record StringReference
    text: string
    length: integer
    positionMap: {integer: common.Position}  -- maps indices to common.Position
end

function StringReference.new(text: string): StringReference
    local function precomputePositionMap(input: string, length: integer): {integer: common.Position}
        local positionMap: {integer: common.Position} = {}
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

    local self: StringReference = setmetatable({}, { __index = StringReference })
    self.text = text
    self.length = #text
    self.positionMap = precomputePositionMap(text, #text)
    return self
end

function StringReference:getPosition(index: integer): common.Position
    local position = self.positionMap[index]
    assert(position ~= nil)
    return position
end

local function tokenizeNonEmptyStringWithValidator(
    textref: StringReference,
    startIndex: integer,
    validEscapes: {string: string},
    readUntilChars: {string: boolean},
    validateChar: function(string): boolean,
    validateFailMessage: string
): common.ParseResult<string>
    local pos = startIndex
    local content = ""
    local warnings: {common.Problem} = {}

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
                -- non-strict mode: invalid backslash as literal
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
    textref: StringReference,
    startIndex: integer,
    validEscapes: {string: string},
    readUntilChars: {string: boolean}
): common.ParseResult<string>
    local function anyCharValidator(_: string): boolean
        return true
    end

    return tokenizeNonEmptyStringWithValidator(
        textref,
        startIndex,
        validEscapes,
        readUntilChars,
        anyCharValidator,
        "unused"
    )
end

local function seekExpectedStrings(
    textref: StringReference,
    startIndex: integer,
    expectedStrings: {string}
): common.ParseResult<string>
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

local function tokenizeTagName(textref: StringReference, startIndex: integer): common.ParseResult<string>
    local validEscapes: {string: string} = {
    }
    local readUntilChars: {string: boolean} = {
        [':'] = true,
        ['>'] = true,
    }
    local function alnumUnderscoreValidator(ch: string): boolean
        return ch:match("^[0-9a-zA-Z_]*$") ~= nil
    end
    local function tagNameValidator(char: string): boolean
        return alnumUnderscoreValidator(char) or char == "#"
    end

    local result = tokenizeNonEmptyStringWithValidator(
        textref,
        startIndex,
        validEscapes,
        readUntilChars,
        tagNameValidator,
        "invalid character in tag name: %s"
    )

    if result is common.ParseReject then
        return common.ParseFail.new(common.Problem.new("tag name cannot be empty", textref:getPosition(startIndex)))
    end

    return result
end

local function tokenizeUnquotedTagArg(textref: StringReference, startIndex: integer): common.ParseResult<lexer.TagSegment>
    local validEscapes: {string: string} = {
    }
    local readUntilChars: {string: boolean} = {
        [':'] = true,
        ['>'] = true,
    }
    local function alnumUnderscoreValidator(ch: string): boolean
        return ch:match("^[0-9a-zA-Z_]*$") ~= nil
    end

    local result = tokenizeNonEmptyStringWithValidator(
        textref,
        startIndex,
        validEscapes,
        readUntilChars,
        alnumUnderscoreValidator,
        "invalid character in unquoted tag argument: %s"
    )

    local isEmptyString = result is common.ParseReject
    local acceptPosition = textref:getPosition(startIndex)

    if isEmptyString then
        local noWarning = {}
        return acceptForLexer(lexer.TagSegment.new(acceptPosition, "", ""), startIndex, noWarning)
    end

    if result is common.ParseFail then
        return result
    end

    assert(result is common.ParseAccept<string>)
    local originalString = textref.text:sub(startIndex, result.nextIndex - 1)

    return acceptForLexer(lexer.TagSegment.new(acceptPosition, result.result, originalString), result.nextIndex, result.warnings)
end

local function tokenizeSingleQuotedTagArg(textref: StringReference, startIndex: integer): common.ParseResult<lexer.TagSegment>
    local seekResult = seekExpectedStrings(textref, startIndex, {"'"})

    if seekResult is common.ParseReject or seekResult is common.ParseFail then
        return common.ParseReject.new()
    end

    local validEscapes: {string: string} = {
        ["\\'"] = "'",
        ['\\\\'] = '\\',
    }
    local readUntilChars: {string: boolean} = {
        ["'"] = true,
    }

    local result = tokenizeNonEmptyString(
        textref,
        seekResult.nextIndex,
        validEscapes,
        readUntilChars
    )

    if result is common.ParseFail then
        return result
    end

    local isEmptyString = result is common.ParseReject
    local endQuotePosition = result is common.ParseAccept<string> and result.nextIndex or startIndex + 1

    local seekResultEnd = seekExpectedStrings(textref, endQuotePosition, {"'"})

    if seekResultEnd is common.ParseReject or seekResultEnd is common.ParseFail then
        return common.ParseFail.new(common.Problem.new("unclosed single-quoted tag argument", textref:getPosition(endQuotePosition)))
    end

    local acceptPosition = textref:getPosition(startIndex)
    local originalString = textref.text:sub(startIndex, seekResultEnd.nextIndex - 1)

    if isEmptyString then
        local noWarning = {}
        return acceptForLexer(lexer.TagSegment.new(acceptPosition, "", originalString), seekResultEnd.nextIndex, noWarning)
    end

    assert(result is common.ParseAccept<string>)
    return acceptForLexer(lexer.TagSegment.new(acceptPosition, result.result, originalString), seekResultEnd.nextIndex, result.warnings)
end

local function tokenizeDoubleQuotedTagArg(textref: StringReference, startIndex: integer): common.ParseResult<lexer.TagSegment>
    local seekResult = seekExpectedStrings(textref, startIndex, {'"'})

    if seekResult is common.ParseReject or seekResult is common.ParseFail then
        return common.ParseReject.new()
    end

    local validEscapes: {string: string} = {
        ['\\"'] = '"',
        ['\\\\'] = '\\',
    }
    local readUntilChars: {string: boolean} = {
        ['"'] = true,
    }

    local result = tokenizeNonEmptyString(
        textref,
        seekResult.nextIndex,
        validEscapes,
        readUntilChars
    )

    if result is common.ParseFail then
        return result
    end

    local isEmptyString = result is common.ParseReject
    local endQuotePosition = result is common.ParseAccept<string> and result.nextIndex or startIndex + 1

    local seekResultEnd = seekExpectedStrings(textref, endQuotePosition, {'"'})

    if seekResultEnd is common.ParseReject or seekResultEnd is common.ParseFail then
        return common.ParseFail.new(common.Problem.new("unclosed double-quoted tag argument", textref:getPosition(endQuotePosition)))
    end

    local acceptPosition = textref:getPosition(startIndex)
    local originalString = textref.text:sub(startIndex, seekResultEnd.nextIndex - 1)

    if isEmptyString then
        local noWarning = {}
        return acceptForLexer(lexer.TagSegment.new(acceptPosition, "", originalString), seekResultEnd.nextIndex, noWarning)
    end

    assert(result is common.ParseAccept<string>)
    return acceptForLexer(lexer.TagSegment.new(acceptPosition, result.result, originalString), seekResultEnd.nextIndex, result.warnings)
end

local function tokenizeTag(textref: StringReference, startIndex: integer): common.ParseResult<lexer.Token>
    local startTagResult = seekExpectedStrings(textref, startIndex, {"</", "<"})

    if startTagResult is common.ParseReject or startTagResult is common.ParseFail then
        return common.ParseReject.new()
    end

    local warnings: {common.Problem} = {}

    local isEndTag = startTagResult.result == "</"

    local tagNameResult = tokenizeTagName(textref, startTagResult.nextIndex)

    if tagNameResult is common.ParseFail then
        -- non-strict mode: display as plain text for invalid tag name
        warnings[#warnings + 1] = tagNameResult.failure
        return acceptForLexer(lexer.PlainTextToken.new(textref:getPosition(startIndex), textref.text:sub(startIndex, tagNameResult.failure.position.index - 1)), tagNameResult.failure.position.index, warnings)
    end

    assert(not tagNameResult is common.ParseReject)

    for _, warning in ipairs(tagNameResult.warnings) do
        warnings[#warnings + 1] = warning
    end

    local pos = tagNameResult.nextIndex
    local tokenizersToTry = { tokenizeDoubleQuotedTagArg, tokenizeSingleQuotedTagArg, tokenizeUnquotedTagArg }
    local arguments: {lexer.TagSegment} = {}

    while pos <= textref.length do
        local seekResult = seekExpectedStrings(textref, pos, {">", ":"})
        if seekResult is common.ParseReject or seekResult is common.ParseFail then
            -- non-strict mode: display as plain text for invalid character in tag
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

        local foundResult: common.ParseAccept<lexer.TagSegment> | nil = nil
        for _, tokenizer in ipairs(tokenizersToTry) do
            local result = tokenizer(textref, pos)
            if result is common.ParseFail then
                -- non-strict mode: display as plain text for invalid tag argument
                warnings[#warnings + 1] = result.failure
                return acceptForLexer(lexer.PlainTextToken.new(textref:getPosition(startIndex), textref.text:sub(startIndex, result.failure.position.index - 1)), result.failure.position.index, warnings)
            end

            if result is common.ParseAccept<lexer.TagSegment> then
                foundResult = result
                break
            end

            -- if reject, continue
        end

        assert(foundResult is common.ParseAccept<lexer.TagSegment>)  -- ensure someone accepted
        arguments[#arguments + 1] = foundResult.result
        pos = foundResult.nextIndex
        for _, warning in ipairs(foundResult.warnings) do
            warnings[#warnings + 1] = warning
        end
    end

    -- non-strict mode: display as plain text for unclosed tag
    warnings[#warnings + 1] = common.Problem.new("unclosed tag", textref:getPosition(pos))
    return acceptForLexer(lexer.PlainTextToken.new(textref:getPosition(startIndex), textref.text:sub(startIndex, pos - 1)), pos, warnings)
end

local function tokenizeNewline(textref: StringReference, startIndex: integer): common.ParseResult<lexer.NewlineToken>
    local result = seekExpectedStrings(textref, startIndex, {"\n"})

    if result is common.ParseReject or result is common.ParseFail then
        return common.ParseReject.new()
    end

    return acceptForLexer(lexer.NewlineToken.new(textref:getPosition(startIndex)), result.nextIndex, {})
end

local function tokenizePlainText(textref: StringReference, startIndex: integer): common.ParseResult<lexer.Token>
    local validEscapes: {string: string} = {
        ['\\<'] = '<',
        ['\\\\'] = '\\',
    }
    local readUntilChars: {string: boolean} = {
        ['<'] = true,
        ['\n'] = true,
    }

    local result = tokenizeNonEmptyString(
        textref,
        startIndex,
        validEscapes,
        readUntilChars
    )

    assert(not result is common.ParseFail)

    if result is common.ParseAccept<string> then
        return acceptForLexer(lexer.PlainTextToken.new(textref:getPosition(startIndex), result.result), result.nextIndex, result.warnings)
    end

    return result
end

function lexer.tokenize(text: string): common.ParseAccept<{lexer.Token}>
    local tokens: {lexer.Token} = {}
    local warnings: {common.Problem} = {}

    local textref: StringReference = StringReference.new(text)

    local pos = 1

    local tokenizersInCycle = { tokenizePlainText, tokenizeNewline, tokenizeTag }

    while pos <= textref.length do
        for _, tokenizer in ipairs(tokenizersInCycle) do
            if pos > textref.length then
                break
            end

            local result = tokenizer(textref, pos)

            if result is common.ParseAccept<lexer.Token> then
                tokens[#tokens + 1] = result.result
                pos = result.nextIndex
                for _, warning in ipairs(result.warnings) do
                    warnings[#warnings + 1] = warning
                end
            end

            assert(not result is common.ParseFail)

            -- if reject, continue
        end
    end

    return acceptForLexer(tokens, pos, warnings)
end

return lexer

