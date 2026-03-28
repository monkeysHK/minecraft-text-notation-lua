local record lexer
    interface Token
        where self.kind

        kind: string
        position: Position
    end

    interface Position
        index: integer
        line: integer
        col: integer
    end

    interface PlainTextToken is Token
        where self.kind == "PlainTextToken"

        content: string
    end

    interface NewlineToken is Token
        where self.kind == "NewlineToken"
    end

    interface TagToken is Token
        where self.kind == "TagToken"

        name: string
        arguments: {TagSegment}
        isEndTag: boolean
        originalString: string
    end

    interface TagSegment
        position: Position
        content: string
        originalString: string
    end

    type TokenizeResult<T> = TokenizeAccept<T> | TokenizeReject | TokenizeFail

    -- Used when tokenizer successfully parses a token
    interface TokenizeAccept<T>
        where self.kind == "TokenizeAccept"

        kind: string
        result: T
        nextIndex: integer
        warnings: {Problem}  -- problems that are errors in strict mode, and should be corrected in non-strict mode
    end

    -- Used when tokenizer determines that this is not the required token
    interface TokenizeReject
        where self.kind == "TokenizeReject"

        kind: string
    end

    -- Used when tokenizer determines that this is the required token
    -- but something was wrong
    interface TokenizeFail
        where self.kind == "TokenizeFail"

        kind: string
        failure: Problem
    end

    interface Problem
        position: Position
        message: string
    end

end

function lexer.makePlainText(position: lexer.Position, content: string): lexer.PlainTextToken
    return { kind = "PlainTextToken", position = position, content = content }
end

function lexer.makeNewline(position: lexer.Position): lexer.NewlineToken
    return { kind = "NewlineToken", position = position }
end

function lexer.makeTag(position: lexer.Position, name: string, arguments: {lexer.TagSegment}, isEndTag: boolean, originalString: string): lexer.TagToken
    return { kind = "TagToken", position = position, name = name, arguments = arguments, isEndTag = isEndTag, originalString = originalString }
end

function lexer.makeTagSegment(position: lexer.Position, content: string, originalString: string): lexer.TagSegment
    return { position = position, content = content, originalString = originalString }
end

function lexer.makePosition(index: integer, line: integer, col: integer): lexer.Position
    return { index = index, line = line, col = col }
end

function lexer.makeProblem(message: string, position: lexer.Position): lexer.Problem
    return { message = message, position = position }
end

function lexer.makeAccept<T>(result: T, nextIndex: integer, warnings: {lexer.Problem}): lexer.TokenizeAccept<T>
    return { kind = "TokenizeAccept", result = result, nextIndex = nextIndex, warnings = warnings }
end

function lexer.makeReject(): lexer.TokenizeReject
    return { kind = "TokenizeReject" }
end

function lexer.makeFail(failure: lexer.Problem): lexer.TokenizeFail
    return { kind = "TokenizeFail", failure = failure }
end

-- Table to pass the text without copying the text
local record StringReference
    text: string
    length: integer
    positionMap: {integer: lexer.Position}  -- maps indices to lexer.Position
end

local function makeStringReference(text: string): StringReference
    local function precomputePositionMap(input: string, length: integer): {integer: lexer.Position}
        local positionMap: {integer: lexer.Position} = {}
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
        positionMap[length + 1] = lexer.makePosition(length + 1, line, col + 1)  -- eof
        return positionMap
    end

    return {
        text = text,
        length = #text,
        positionMap = precomputePositionMap(text, #text),
    }
end

local function makePosition(index: integer, textref: StringReference): lexer.Position
    local position = textref.positionMap[index]
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
): lexer.TokenizeResult<string>
    local pos = startIndex
    local content = ""
    local warnings: {lexer.Problem} = {}

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
                -- non-strict mode: invalid backslash as literal
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
    textref: StringReference,
    startIndex: integer,
    validEscapes: {string: string},
    readUntilChars: {string: boolean}
): lexer.TokenizeResult<string>
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
): lexer.TokenizeResult<string>
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

local function tokenizeTagName(textref: StringReference, startIndex: integer): lexer.TokenizeResult<string>
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

    if result is lexer.TokenizeReject then
        return lexer.makeFail(lexer.makeProblem("tag name cannot be empty", makePosition(startIndex, textref)))
    end

    return result
end

local function tokenizeUnquotedTagArg(textref: StringReference, startIndex: integer): lexer.TokenizeResult<lexer.TagSegment>
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

    local isEmptyString = result is lexer.TokenizeReject
    local acceptPosition = makePosition(startIndex, textref)

    if isEmptyString then
        local noWarning = {}
        return lexer.makeAccept(lexer.makeTagSegment(acceptPosition, "", ""), startIndex, noWarning)
    end

    if result is lexer.TokenizeFail then
        return result
    end

    assert(result is lexer.TokenizeAccept<string>)
    local originalString = textref.text:sub(startIndex, result.nextIndex - 1)

    return lexer.makeAccept(lexer.makeTagSegment(acceptPosition, result.result, originalString), result.nextIndex, result.warnings)
end

local function tokenizeSingleQuotedTagArg(textref: StringReference, startIndex: integer): lexer.TokenizeResult<lexer.TagSegment>
    local seekResult = seekExpectedStrings(textref, startIndex, {"'"})

    if seekResult is lexer.TokenizeReject or seekResult is lexer.TokenizeFail then
        return lexer.makeReject()
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

    if result is lexer.TokenizeFail then
        return result
    end

    local isEmptyString = result is lexer.TokenizeReject
    local endQuotePosition = result is lexer.TokenizeAccept<string> and result.nextIndex or startIndex + 1

    local seekResultEnd = seekExpectedStrings(textref, endQuotePosition, {"'"})

    if seekResultEnd is lexer.TokenizeReject or seekResultEnd is lexer.TokenizeFail then
        return lexer.makeFail(lexer.makeProblem("unclosed single-quoted tag argument", makePosition(endQuotePosition, textref)))
    end

    local acceptPosition = makePosition(startIndex, textref)
    local originalString = textref.text:sub(startIndex, seekResultEnd.nextIndex - 1)

    if isEmptyString then
        local noWarning = {}
        return lexer.makeAccept(lexer.makeTagSegment(acceptPosition, "", originalString), seekResultEnd.nextIndex, noWarning)
    end

    assert(result is lexer.TokenizeAccept<string>)
    return lexer.makeAccept(lexer.makeTagSegment(acceptPosition, result.result, originalString), seekResultEnd.nextIndex, result.warnings)
end

local function tokenizeDoubleQuotedTagArg(textref: StringReference, startIndex: integer): lexer.TokenizeResult<lexer.TagSegment>
    local seekResult = seekExpectedStrings(textref, startIndex, {'"'})

    if seekResult is lexer.TokenizeReject or seekResult is lexer.TokenizeFail then
        return lexer.makeReject()
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

    if result is lexer.TokenizeFail then
        return result
    end

    local isEmptyString = result is lexer.TokenizeReject
    local endQuotePosition = result is lexer.TokenizeAccept<string> and result.nextIndex or startIndex + 1

    local seekResultEnd = seekExpectedStrings(textref, endQuotePosition, {'"'})

    if seekResultEnd is lexer.TokenizeReject or seekResultEnd is lexer.TokenizeFail then
        return lexer.makeFail(lexer.makeProblem("unclosed double-quoted tag argument", makePosition(endQuotePosition, textref)))
    end

    local acceptPosition = makePosition(startIndex, textref)
    local originalString = textref.text:sub(startIndex, seekResultEnd.nextIndex - 1)

    if isEmptyString then
        local noWarning = {}
        return lexer.makeAccept(lexer.makeTagSegment(acceptPosition, "", originalString), seekResultEnd.nextIndex, noWarning)
    end

    assert(result is lexer.TokenizeAccept<string>)
    return lexer.makeAccept(lexer.makeTagSegment(acceptPosition, result.result, originalString), seekResultEnd.nextIndex, result.warnings)
end

local function tokenizeTag(textref: StringReference, startIndex: integer): lexer.TokenizeResult<lexer.Token>
    local startTagResult = seekExpectedStrings(textref, startIndex, {"</", "<"})

    if startTagResult is lexer.TokenizeReject or startTagResult is lexer.TokenizeFail then
        return lexer.makeReject()
    end

    local warnings: {lexer.Problem} = {}

    local isEndTag = startTagResult.result == "</"

    local tagNameResult = tokenizeTagName(textref, startTagResult.nextIndex)

    if tagNameResult is lexer.TokenizeFail then
        -- non-strict mode: display as plain text for invalid tag name
        warnings[#warnings + 1] = tagNameResult.failure
        return lexer.makeAccept(lexer.makePlainText(makePosition(startIndex, textref), textref.text:sub(startIndex, tagNameResult.failure.position.index - 1)), tagNameResult.failure.position.index, warnings)
    end

    assert(not tagNameResult is lexer.TokenizeReject)

    for _, warning in ipairs(tagNameResult.warnings) do
        warnings[#warnings + 1] = warning
    end

    local pos = tagNameResult.nextIndex
    local tokenizersToTry = { tokenizeDoubleQuotedTagArg, tokenizeSingleQuotedTagArg, tokenizeUnquotedTagArg }
    local arguments: {lexer.TagSegment} = {}

    while pos <= textref.length do
        local seekResult = seekExpectedStrings(textref, pos, {">", ":"})
        if seekResult is lexer.TokenizeReject or seekResult is lexer.TokenizeFail then
            -- non-strict mode: display as plain text for invalid character in tag
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

        local foundResult: lexer.TokenizeAccept<lexer.TagSegment> | nil = nil
        for _, tokenizer in ipairs(tokenizersToTry) do
            local result = tokenizer(textref, pos)
            if result is lexer.TokenizeFail then
                -- non-strict mode: display as plain text for invalid tag argument
                warnings[#warnings + 1] = result.failure
                return lexer.makeAccept(lexer.makePlainText(makePosition(startIndex, textref), textref.text:sub(startIndex, result.failure.position.index - 1)), result.failure.position.index, warnings)
            end

            if result is lexer.TokenizeAccept<lexer.TagSegment> then
                foundResult = result
                break
            end

            -- if reject, continue
        end

        assert(foundResult is lexer.TokenizeAccept<lexer.TagSegment>)  -- ensure someone accepted
        arguments[#arguments + 1] = foundResult.result
        pos = foundResult.nextIndex
        for _, warning in ipairs(foundResult.warnings) do
            warnings[#warnings + 1] = warning
        end
    end

    -- non-strict mode: display as plain text for unclosed tag
    warnings[#warnings + 1] = lexer.makeProblem("unclosed tag", makePosition(pos, textref))
    return lexer.makeAccept(lexer.makePlainText(makePosition(startIndex, textref), textref.text:sub(startIndex, pos - 1)), pos, warnings)
end

local function tokenizeNewline(textref: StringReference, startIndex: integer): lexer.TokenizeResult<lexer.NewlineToken>
    local result = seekExpectedStrings(textref, startIndex, {"\n"})

    if result is lexer.TokenizeReject or result is lexer.TokenizeFail then
        return lexer.makeReject()
    end

    return lexer.makeAccept(lexer.makeNewline(makePosition(startIndex, textref)), result.nextIndex, {})
end

local function tokenizePlainText(textref: StringReference, startIndex: integer): lexer.TokenizeResult<lexer.Token>
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

    assert(not result is lexer.TokenizeFail)

    if result is lexer.TokenizeAccept<string> then
        return lexer.makeAccept(lexer.makePlainText(makePosition(startIndex, textref), result.result), result.nextIndex, result.warnings)
    end

    return result
end

function lexer.tokenize(text: string): lexer.TokenizeAccept<{lexer.Token}>
    local tokens: {lexer.Token} = {}
    local warnings: {lexer.Problem} = {}

    local textref: StringReference = makeStringReference(text)

    local pos = 1

    local tokenizersInCycle = { tokenizePlainText, tokenizeNewline, tokenizeTag }

    while pos <= textref.length do
        for _, tokenizer in ipairs(tokenizersInCycle) do
            if pos > textref.length then
                break
            end

            local result = tokenizer(textref, pos)

            if result is lexer.TokenizeAccept<lexer.Token> then
                tokens[#tokens + 1] = result.result
                pos = result.nextIndex
                for _, warning in ipairs(result.warnings) do
                    warnings[#warnings + 1] = warning
                end
            end

            assert(not result is lexer.TokenizeFail)

            -- if reject, continue
        end
    end

    return lexer.makeAccept(tokens, pos, warnings)
end

return lexer

