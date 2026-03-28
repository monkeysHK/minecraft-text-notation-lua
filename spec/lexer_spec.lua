local lexer = require("lexer")

local function extractResult(tokenizeResult)
    assert.equal("TokenizeAccept", tokenizeResult.kind)
    assert.equal("table", type(tokenizeResult.result))
    assert.equal("table", type(tokenizeResult.warnings))
    return tokenizeResult.result, tokenizeResult.warnings
end

local function extractResultNoWarn(tokenizeResult)
    local result, warnings = extractResult(tokenizeResult)
    assert.are.same({}, warnings, "expect result to have no warning")
    return result
end

local function position(index, row, col)
    return lexer.makePosition(index, row, col)
end

local function lineonepos(index)
    return lexer.makePosition(index, 1, index)
end

local function problem(message, position)
    return lexer.makeProblem(message, position)
end

local function plainText(position, content)
    return lexer.makePlainText(position, content)
end

local function newline(position)
    return lexer.makeNewline(position)
end

local function tag(position, name, arguments, isEndTag, originalString)
    return lexer.makeTag(position, name, arguments, isEndTag, originalString)
end

local function tagSegment(position, content, originalString)
    return lexer.makeTagSegment(position, content, originalString)
end

describe("plain text and basic string parsing", function()

    it("expect empty string can be parsed", function()
        local output = lexer.tokenize("")
        local result = extractResultNoWarn(output)

        assert.are.same({}, result)
    end)

    it("expect simple plain text can be parsed", function()
        local output = lexer.tokenize("abc")
        local result = extractResultNoWarn(output)

        assert.are.same({ plainText(lineonepos(1), "abc") }, result)
    end)

    it("expect whitespaces are not stripped", function()
        local output = lexer.tokenize("   ")
        local result = extractResultNoWarn(output)

        assert.are.same({ plainText(lineonepos(1), "   ") }, result)
    end)

    it("expect non-special characters can be parsed", function()
        local output = lexer.tokenize(">/:")
        local result = extractResultNoWarn(output)

        assert.are.same({ plainText(lineonepos(1), ">/:") }, result)
    end)

    it("expect special characters can be escaped", function()
        local output = lexer.tokenize("\\<\\\\")
        local result = extractResultNoWarn(output)

        assert.are.same({ plainText(lineonepos(1), "<\\") }, result)
    end)

    it("expect invalid escapes to be expressed as literals", function()
        local output = lexer.tokenize("\\o \\u")
        local result, warnings = extractResult(output)

        assert.are.same({ plainText(lineonepos(1), "\\o \\u") }, result)
        assert.are.same({ problem("invalid escape \\o", lineonepos(1)), problem("invalid escape \\u", position(4, 1, 4)) }, warnings)
    end)

    it("expect end of file invalid escape is handled", function()
        local output = lexer.tokenize("-->\\")
        local result, warnings = extractResult(output)

        assert.are.same({ plainText(lineonepos(1), "-->\\") }, result)
        assert.are.same({ problem("invalid escape \\", lineonepos(4)) }, warnings)
    end)

    it("expect newline can be parsed", function()
        local output = lexer.tokenize("\n")
        local result = extractResultNoWarn(output)

        assert.are.same({ newline(lineonepos(1)) }, result)
    end)

end)

describe("open tag, close tag, and tag name", function ()

    it("expect simple tag can be parsed", function()
        local output = lexer.tokenize("<d_v>")
        local result = extractResultNoWarn(output)

        assert.are.same({ tag(lineonepos(1), "d_v", {}, false, "<d_v>") }, result)
    end)

    it("expect close tag can be parsed", function()
        local output = lexer.tokenize("</d_v>")
        local result = extractResultNoWarn(output)

        assert.are.same({ tag(lineonepos(1), "d_v", {}, true, "</d_v>") }, result)
    end)

    it("expect empty tag to fail", function()
        local output = lexer.tokenize("<>")
        local result, warnings = extractResult(output)

        assert.are.same({ plainText(lineonepos(1), "<"), plainText(lineonepos(2), ">") }, result)
        assert.are.same({ problem("tag name cannot be empty", lineonepos(2)) }, warnings)
    end)

    it("expect tag name with # can be parsed", function()
        local output = lexer.tokenize("<#ababab>")
        local result = extractResultNoWarn(output)

        assert.are.same({ tag(lineonepos(1), "#ababab", {}, false, "<#ababab>") }, result)
    end)

    it("expect tag name with non-compliant characters to fail", function()
        local output = lexer.tokenize("<bad+*>")
        local result, warnings = extractResult(output)

        assert.are.same({ plainText(lineonepos(1), "<bad"), plainText(lineonepos(5), "+*>") }, result)
        assert.are.same({ problem("invalid character in tag name: +", lineonepos(5)) }, warnings)
    end)

    it("expect unclosed tag to fail", function()
        local output = lexer.tokenize("<bad")
        local result, warnings = extractResult(output)

        assert.are.same({ plainText(lineonepos(1), "<bad") }, result)
        assert.are.same({ problem("unclosed tag", lineonepos(5)) }, warnings)
    end)

end)

describe("tag argument", function()

    describe("unquoted", function ()

        it("expect empty tag argument can be parsed", function()
            local output = lexer.tokenize("<tag:>")
            local result = extractResultNoWarn(output)

            assert.are.same({ tag(lineonepos(1), "tag", { tagSegment(lineonepos(6), "", "") }, false, "<tag:>") }, result)
        end)

        it("expect simple tag argument can be parsed", function()
            local output = lexer.tokenize("<tag:arg>")
            local result = extractResultNoWarn(output)

            assert.are.same({ tag(lineonepos(1), "tag", { tagSegment(lineonepos(6), "arg", "arg") }, false, "<tag:arg>") }, result)
        end)

        it("expect non-compliant character to fail", function()
            local output = lexer.tokenize("<tag:bad*+>")
            local result, warnings = extractResult(output)

            assert.are.same({ plainText(lineonepos(1), "<tag:bad"), plainText(lineonepos(9), "*+>") }, result)
            assert.are.same({ problem("invalid character in unquoted tag argument: *", lineonepos(9)) }, warnings)
        end)

    end)

    describe("single-quoted", function ()

        it("expect empty tag argument can be parsed", function()
            local output = lexer.tokenize("<tag:''>")
            local result = extractResultNoWarn(output)

            assert.are.same({ tag(lineonepos(1), "tag", { tagSegment(lineonepos(6), "", "''") }, false, "<tag:''>") }, result)
        end)

        it("expect simple tag argument can be parsed", function()
            local output = lexer.tokenize("<tag:'arg'>")
            local result = extractResultNoWarn(output)

            assert.are.same({ tag(lineonepos(1), "tag", { tagSegment(lineonepos(6), "arg", "'arg'") }, false, "<tag:'arg'>") }, result)
        end)

        it("expect whitespaces are not stripped", function()
            local output = lexer.tokenize("<tag:'   '>")
            local result = extractResultNoWarn(output)

            assert.are.same({ tag(lineonepos(1), "tag", { tagSegment(lineonepos(6), "   ", "'   '") }, false, "<tag:'   '>") }, result)
        end)

        it("expect non-special characters can be parsed", function()
            local output = lexer.tokenize("<tag:'\"<>/:'>")
            local result = extractResultNoWarn(output)

            assert.are.same({ tag(lineonepos(1), "tag", { tagSegment(lineonepos(6), '"<>/:', "'\"<>/:'") }, false, "<tag:'\"<>/:'>") }, result)
        end)

        it("expect special characters can be escaped", function()
            local output = lexer.tokenize("<tag:'\\'\\\\'>")
            local result = extractResultNoWarn(output)

            assert.are.same({ tag(lineonepos(1), "tag", { tagSegment(lineonepos(6), "'\\", "'\\'\\\\'") }, false, "<tag:'\\'\\\\'>") }, result)
        end)

        it("expect unclosed quote to fail", function()
            local output = lexer.tokenize("<tag:'")
            local result, warnings = extractResult(output)

            assert.are.same({ plainText(lineonepos(1), "<tag:'") }, result)
            assert.are.same({ problem("unclosed single-quoted tag argument", lineonepos(7)) }, warnings)
        end)

    end)

    describe("double-quoted", function ()

        it("expect empty tag argument can be parsed", function()
            local output = lexer.tokenize('<tag:"">')
            local result = extractResultNoWarn(output)

            assert.are.same({ tag(lineonepos(1), "tag", { tagSegment(lineonepos(6), "", '""') }, false, '<tag:"">') }, result)
        end)

        it("expect simple tag argument can be parsed", function()
            local output = lexer.tokenize('<tag:"arg">')
            local result = extractResultNoWarn(output)

            assert.are.same({ tag(lineonepos(1), "tag", { tagSegment(lineonepos(6), "arg", '"arg"') }, false, '<tag:"arg">') }, result)
        end)

        it("expect whitespaces are not stripped", function()
            local output = lexer.tokenize('<tag:"   ">')
            local result = extractResultNoWarn(output)

            assert.are.same({ tag(lineonepos(1), "tag", { tagSegment(lineonepos(6), "   ", '"   "') }, false, '<tag:"   ">') }, result)
        end)

        it("expect non-special characters can be parsed", function()
            local output = lexer.tokenize('<tag:"\'<>/:">')
            local result = extractResultNoWarn(output)

            assert.are.same({ tag(lineonepos(1), "tag", { tagSegment(lineonepos(6), "'<>/:", '"\'<>/:"') }, false, '<tag:"\'<>/:">') }, result)
        end)

        it("expect special characters can be escaped", function()
            local output = lexer.tokenize('<tag:"\\"\\\\">')
            local result = extractResultNoWarn(output)

            assert.are.same({ tag(lineonepos(1), "tag", { tagSegment(lineonepos(6), '"\\', '"\\"\\\\"') }, false, '<tag:"\\"\\\\">') }, result)
        end)

        it("expect unclosed quote to fail", function()
            local output = lexer.tokenize('<tag:"')
            local result, warnings = extractResult(output)

            assert.are.same({ plainText(lineonepos(1), '<tag:"') }, result)
            assert.are.same({ problem("unclosed double-quoted tag argument", lineonepos(7)) }, warnings)
        end)

    end)

    it("expect consecutive quoted strings to fail", function()
        local output = lexer.tokenize('<tag:\'arg\'"arg">')
        local result, warnings = extractResult(output)

        assert.are.same({ plainText(lineonepos(1), '<tag:\'arg\''), plainText(lineonepos(11), '"arg">') }, result)
        assert.are.same({ problem('invalid character in tag: "', lineonepos(11)) }, warnings)
    end)

    it("expect multiple arguments can be parsed", function()
        local output = lexer.tokenize("<tag::arg1:'arg2':\"arg3\">")
        local result = extractResultNoWarn(output)

        local tagArgs = {
            tagSegment(lineonepos(6), "", ""),
            tagSegment(lineonepos(7), "arg1", "arg1"),
            tagSegment(lineonepos(12), "arg2", "'arg2'"),
            tagSegment(lineonepos(19), "arg3", '"arg3"'),
        }
        assert.are.same({ tag(lineonepos(1), "tag", tagArgs, false, "<tag::arg1:'arg2':\"arg3\">") }, result)
    end)

end)

it("expect multiple tokens can be parsed", function()
    local output = lexer.tokenize("<bold>Hello</bold>")
    local result = extractResultNoWarn(output)

    assert.are.same({
        tag(lineonepos(1), "bold", {}, false, "<bold>"),
        plainText(lineonepos(7), "Hello"),
        tag(lineonepos(12), "bold", {}, true, "</bold>")
    }, result)
end)

it("expect parsing resumes at failure position", function()
    local output = lexer.tokenize("<<bold>")
    local result, warnings = extractResult(output)

    assert.are.same({
        plainText(lineonepos(1), "<"),
        tag(lineonepos(2), "bold", {}, false, "<bold>"),
    }, result)
    assert.are.same({
        problem("invalid character in tag name: <", lineonepos(2)),
    }, warnings)
end)

it("expect multiple warnings can be given", function()
    local output = lexer.tokenize("<bo\\ld>He\\llo</")
    local result, warnings = extractResult(output)

    assert.are.same({
        plainText(lineonepos(1), "<bo"),
        plainText(lineonepos(4), "\\ld>He\\llo"),
        plainText(lineonepos(14), "</"),
    }, result)
    assert.are.same({
        problem("invalid character in tag name: \\", lineonepos(4)),
        problem("invalid escape \\l", lineonepos(4)),
        problem("invalid escape \\l", lineonepos(10)),
        problem("tag name cannot be empty", lineonepos(16)),
    }, warnings)
end)

it("expect positions have correct line and col numbers", function()
    local output = lexer.tokenize("Line 1\n\\")
    local result, warnings = extractResult(output)

    assert.are.same({
        plainText(lineonepos(1), "Line 1"),
        newline(lineonepos(7)),
        plainText(position(8, 2, 1), "\\"),
    }, result)
    assert.are.same({ problem("invalid escape \\", position(8, 2, 1)) }, warnings)
end)

