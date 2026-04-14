local lexer = require("lexer")
local parser = require("parser")

local function plainTextToken(position, content)
    return lexer.PlainTextToken.new(position, content)
end

local function newlineToken(position)
    return lexer.NewlineToken.new(position)
end

local function tagToken(position, name, arguments, isEndTag, originalString)
    return lexer.TagToken.new(position, name, arguments, isEndTag, originalString)
end

local function tagSegment(position, content, originalString)
    return lexer.TagSegment.new(position, content, originalString)
end

local function extractResult(parseResult)
    assert.equal("ParseAccept", parseResult.kind)
    assert.equal("table", type(parseResult.result))
    assert.equal("table", type(parseResult.warnings))
    assert.equal("table", type(parseResult.strictProblems))
    return parseResult.result, parseResult.warnings, parseResult.strictProblems
end

local function expectNoWarning(parseResult)
    assert.are.same({}, parseResult.warnings, "expect result to have no warning")
end

local function expectNoStrictProblem(parseResult)
    assert.are.same({}, parseResult.strictProblems, "expect result to have no strict problem")
end

local function position(index, row, col)
    return lexer.Position.new(index, row, col)
end

local function lineonepos(index)
    return lexer.Position.new(index, 1, index)
end

local function problem(message, position)
    return lexer.Problem.new(message, position)
end

local function minecraftText(position, components)
    return parser.MinecraftTextNode.new(position, components)
end

local function namedColor(position, color, components)
    return parser.NamedColorNode.new(position, color, components)
end

local function hexColor(position, color, components)
    return parser.HexColorNode.new(position, color, components)
end

local function decoration(position, decorationName, components)
    return parser.DecorationNode.new(position, decorationName, components)
end

local function showText(position, text, textPosition, originalString, components)
    return parser.ShowTextNode.new(position, text, textPosition, originalString, components)
end

local function newline(position)
    return parser.NewlineNode.new(position)
end

local function plainText(position, content)
    return parser.PlainTextNode.new(position, content)
end

describe("plain text", function()

    it("expect empty can be parsed", function()
        local output = parser.parse({})
        local result = extractResult(output)
        expectNoWarning(output)
        expectNoStrictProblem(output)

        assert.are.same(minecraftText(lineonepos(1), {}), result)
    end)

    it("expect plain text can be parsed", function()
        local output = parser.parse({plainTextToken(lineonepos(1), "some text")})
        local result = extractResult(output)
        expectNoWarning(output)
        expectNoStrictProblem(output)

        assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "some text")}), result)
    end)

    it("expect newline can be parsed", function()
        local output = parser.parse({newlineToken(lineonepos(1))})
        local result = extractResult(output)
        expectNoWarning(output)
        expectNoStrictProblem(output)

        assert.are.same(minecraftText(lineonepos(1), {newline(lineonepos(1))}), result)
    end)

end)

describe("br tag", function()

    it("expect br tag can be parsed", function()
        local output = parser.parse({tagToken(lineonepos(1), "br", {}, false, "<br>")})
        local result = extractResult(output)
        expectNoWarning(output)
        expectNoStrictProblem(output)

        assert.are.same(minecraftText(lineonepos(1), {newline(lineonepos(1))}), result)
    end)

    it("expect br tag with >= 1 args to be invalid", function()
        local output = parser.parse({tagToken(lineonepos(1), "br", {tagSegment(lineonepos(5), "arg", "arg")}, false, "<br:arg>")})
        local result, warnings = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<br:arg>")}), result)
        assert.are.same({ problem("too many argument in br tag", lineonepos(1)) }, warnings)
    end)

end)

describe("named color tag", function()

    it("expect all named color tags can be parsed", function()
        local namedColors = { "black", "dark_blue", "dark_green", "dark_aqua", "dark_red", "dark_purple", "gold", "gray", "dark_gray", "blue", "green", "aqua", "red", "light_purple", "yellow", "white" }
        for _, color in ipairs(namedColors) do
            local output = parser.parse({tagToken(lineonepos(1), color, {}, false, "<" .. color .. ">")})
            local result = extractResult(output)
            expectNoWarning(output)

            assert.are.same(minecraftText(lineonepos(1), {namedColor(lineonepos(1), color, {})}), result)
        end
    end)

    it("expect named color tags with >= 1 args to be invalid", function()
        local output = parser.parse({tagToken(lineonepos(1), "black", {tagSegment(lineonepos(8), "arg", "arg")}, false, "<black:arg>")})
        local result, warnings = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<black:arg>")}), result)
        assert.are.same({ problem("too many argument in named color tag", lineonepos(1)) }, warnings)
    end)

end)

describe("hex color tag", function()

    it("expect hex color tag can be parsed", function()
        local output = parser.parse({tagToken(lineonepos(1), "#012abc", {}, false, "<#012abc>")})
        local result = extractResult(output)
        expectNoWarning(output)

        assert.are.same(minecraftText(lineonepos(1), {hexColor(lineonepos(1), "012abc", {})}), result)
    end)

    it("expect hex color tag with >= 1 args to be invalid", function()
        local output = parser.parse({tagToken(lineonepos(1), "#abcdef", {tagSegment(lineonepos(10), "arg", "arg")}, false, "<#abcdef:arg>")})
        local result, warnings = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<#abcdef:arg>")}), result)
        assert.are.same({ problem("too many argument in hex color tag", lineonepos(1)) }, warnings)
    end)

    it("expect malformed hex color tag to be invalid", function()
        local badTags = { "abcdef", "#abc", "#ghijkl" }

        for _, tag in ipairs(badTags) do
            local output = parser.parse({tagToken(lineonepos(1), tag, {}, false, "<" .. tag .. ">")})
            local result, warnings = extractResult(output)

            assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<" .. tag .. ">")}), result)
            assert.are.same({ problem("unknown tag " .. tag, lineonepos(1)) }, warnings)
        end
    end)

end)

describe("color tag", function()

    it("expect color tag with named color can be parsed", function()
        local output = parser.parse({tagToken(lineonepos(1), "color", {tagSegment(lineonepos(8), "black", "black")}, false, "<color:black>")})
        local result = extractResult(output)
        expectNoWarning(output)

        assert.are.same(minecraftText(lineonepos(1), {namedColor(lineonepos(1), "black", {})}), result)
    end)

    it("expect color tag with hex color can be parsed", function()
        local output = parser.parse({tagToken(lineonepos(1), "color", {tagSegment(lineonepos(8), "#123def", false)}, false, "<color:#123def>")})
        local result = extractResult(output)
        expectNoWarning(output)

        assert.are.same(minecraftText(lineonepos(1), {hexColor(lineonepos(1), "123def", {})}), result)
    end)

    it("expect color tag with unknown color to be invalid", function()
        local output = parser.parse({tagToken(lineonepos(1), "color", {tagSegment(lineonepos(8), "unknown", "unknown")}, false, "<color:unknown>")})
        local result, warnings = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<color:unknown>")}), result)
        assert.are.same({ problem("invalid color name unknown in color tag", lineonepos(1)) }, warnings)
    end)

    it("expect color tag with 0 args to be invalid", function()
        local output = parser.parse({tagToken(lineonepos(1), "color", {}, false, "<color>")})
        local result, warnings = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<color>")}), result)
        assert.are.same({ problem("not enough argument in color tag", lineonepos(1)) }, warnings)
    end)

    it("expect color tag with >= 2 args to be invalid", function()
        local output = parser.parse({tagToken(lineonepos(1), "color", {tagSegment(lineonepos(8), "#123def", "#123def"), tagSegment(lineonepos(16), "arg2", "arg2")}, false, "<color:#123def:arg2>")})
        local result, warnings = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<color:#123def:arg2>")}), result)
        assert.are.same({ problem("too many argument in color tag", lineonepos(1)) }, warnings)
    end)

end)

describe("decoration tag", function()

    it("expect all decoration tags can be parsed", function()
        local tests = {
            { tag = "bold", result = "bold" },
            { tag = "b", result = "bold" },
            { tag = "italic", result = "italic" },
            { tag = "i", result = "italic" },
            { tag = "underlined", result = "underlined" },
            { tag = "u", result = "underlined" },
            { tag = "strikethrough", result = "strikethrough" },
            { tag = "st", result = "strikethrough" },
            { tag = "obfuscated", result = "obfuscated" },
            { tag = "obf", result = "obfuscated" },
        }

        for _, test in pairs(tests) do
            local output = parser.parse({tagToken(lineonepos(1), test.tag, {}, false, "<" .. test.tag .. ">")})
            local result = extractResult(output)
            expectNoWarning(output)

            assert.are.same(minecraftText(lineonepos(1), {decoration(lineonepos(1), test.result, {})}), result)
        end
    end)

    it("expect decoration tag with >= 1 args to be invalid", function()
        local output = parser.parse({tagToken(lineonepos(1), "bold", {tagSegment(lineonepos(7), "arg1", "arg1")}, false, "<bold:arg1>")})
        local result, warnings = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<bold:arg1>")}), result)
        assert.are.same({ problem("too many argument in bold tag", lineonepos(1)) }, warnings)
    end)

end)

describe("hover tag", function()

    it("expect hover tag with <= 1 args to be invalid", function ()
        local output = parser.parse({tagToken(lineonepos(1), "hover", {}, false, "<hover>")})
        local result, warnings = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<hover>")}), result)
        assert.are.same({ problem("not enough argument for hover tag", lineonepos(1)) }, warnings)
    end)

    it("expect unknown hover tag to be invalid", function ()
        local output = parser.parse({tagToken(lineonepos(1), "hover", {tagSegment(lineonepos(8), "unknown", "unknown")}, false, "<hover:unknown>")})
        local result, warnings = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<hover:unknown>")}), result)
        assert.are.same({ problem("invalid hover tag action", lineonepos(1)) }, warnings)
    end)

    describe("show_text tag", function()

        it("expect empty text can be parsed", function()
            local output = parser.parse({tagToken(lineonepos(1), "hover", {tagSegment(lineonepos(8), "show_text", "show_text"), tagSegment(lineonepos(18), "", "")}, false, "<hover:show_text:>")})
            local result = extractResult(output)
            expectNoWarning(output)

            assert.are.same(minecraftText(lineonepos(1), {showText(lineonepos(1), "", lineonepos(18), "", {})}), result)
        end)

        it("expect non-empty text can be parsed", function()
            local output = parser.parse({tagToken(lineonepos(1), "hover", {tagSegment(lineonepos(8), "show_text", "show_text"), tagSegment(lineonepos(18), "some text", "'some text'")}, false, "<hover:show_text:'some text'>")})
            local result = extractResult(output)
            expectNoWarning(output)

            assert.are.same(minecraftText(lineonepos(1), {showText(lineonepos(1), "some text", lineonepos(18), "'some text'", {})}), result)
        end)

        it("expect show text tag with <= 1 args to be invalid", function()
            local output = parser.parse({tagToken(lineonepos(1), "hover", {tagSegment(lineonepos(8), "show_text", "show_text")}, false, "<hover:show_text>")})
            local result, warnings = extractResult(output)

            assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<hover:show_text>")}), result)
            assert.are.same({ problem("not enough argument for hover:show_text tag", lineonepos(1)) }, warnings)
        end)

        it("expect show text tag with >= 3 args to be invalid", function()
            local output = parser.parse({tagToken(lineonepos(1), "hover", {tagSegment(lineonepos(8), "show_text", "show_text"), tagSegment(lineonepos(18), "text", "text"), tagSegment(lineonepos(23), "arg3", "arg3")}, false, "<hover:show_text:text:arg3>")})
            local result, warnings = extractResult(output)

            assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<hover:show_text:text:arg3>")}), result)
            assert.are.same({ problem("too many argument for hover:show_text tag", lineonepos(1)) }, warnings)
        end)

    end)

end)

describe("reset tag", function()

    it("expect reset tag to not produce node", function()
        local output = parser.parse({ tagToken(lineonepos(1), "reset", {}, false, "<reset>") })
        local result, warnings, _ = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {}), result)
        assert.are.same({}, warnings)
    end)

    it("expect reset tag to be disallowed in strict mode", function()
        local output = parser.parse({ tagToken(lineonepos(1), "reset", {}, false, "<reset>") })
        local _, _, strictProblems = extractResult(output)

        assert.are.same({ problem("reset tag is not allowed", lineonepos(1)) }, strictProblems)
    end)

    it("expect reset tag with >= 1 args to be invalid", function()
        local output = parser.parse({ tagToken(lineonepos(1), "reset", {tagSegment(lineonepos(8), "arg", "arg")}, false, "<reset:arg>") })
        local result, warnings, _ = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "<reset:arg>")}), result)
        assert.are.same({ problem("too many argument in reset tag", lineonepos(1)) }, warnings)
    end)

end)

describe("tag tree", function()

    it("expect unknown tag to be invalid", function()
        local output = parser.parse({ tagToken(lineonepos(1), "unknown", {}, false, "<unknown>"), })
        local _, warnings = extractResult(output)

        assert.are.same({ problem("unknown tag unknown", lineonepos(1)) }, warnings)

    end)

    it("expect normal tag can have components", function()
        local output = parser.parse({
            tagToken(lineonepos(1), "b", {}, false, "<b>"),
            plainTextToken(lineonepos(1), "some text"),
            tagToken(lineonepos(13), "b", {}, true, "</b>")
        })
        local result = extractResult(output)
        expectNoWarning(output)
        expectNoStrictProblem(output)

        assert.are.same(minecraftText(lineonepos(1), {decoration(lineonepos(1), "bold", {plainText(lineonepos(1), "some text")})}), result)
    end)

    it("expect invalid end tag to display as plain text", function()
        local output = parser.parse({
            tagToken(lineonepos(1), "bad", {}, true, "</bad>")
        })
        local result, warnings = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {plainText(lineonepos(1), "</bad>")}), result)
        assert.are.same({ problem("invalid end tag bad", lineonepos(1)) }, warnings)
    end)

    it("expect unmatched end tag to display as plain text", function()
        local output = parser.parse({
            tagToken(lineonepos(1), "b", {}, false, "<b>"),
            plainTextToken(lineonepos(4), "some text"),
            tagToken(lineonepos(13), "i", {}, true, "</i>")
        })
        local result, warnings = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {decoration(lineonepos(1), "bold", {plainText(lineonepos(4), "some text"), plainText(lineonepos(13), "</i>")})}), result)
        assert.are.same({ problem("invalid end tag i", lineonepos(13)) }, warnings)
    end)

    it("expect closing void tag is invalid", function()
        local output = parser.parse({
            tagToken(lineonepos(1), "br", {}, false, "<br>"),
            tagToken(lineonepos(5), "br", {}, true, "</br>")
        })
        local result, warnings = extractResult(output)

        assert.are.same(minecraftText(lineonepos(1), {newline(lineonepos(1)), plainText(lineonepos(5), "</br>")}), result)
        assert.are.same({ problem("invalid end tag br", lineonepos(5)) }, warnings)
    end)

    describe("tag matching and resetting", function()

        it("expect end tag can be paired with matching start tag", function()
            local output = parser.parse({
                tagToken(lineonepos(1), "b", {}, false, "<b>"),
                tagToken(lineonepos(4), "b", {}, true, "</b>")
            })
            local result = extractResult(output)
            expectNoWarning(output)
            expectNoStrictProblem(output)

            assert.are.same(minecraftText(lineonepos(1), {decoration(lineonepos(1), "bold", {})}), result)
        end)

        it("expect tags with different tag name do not match", function()
            local output = parser.parse({
                tagToken(lineonepos(1), "hover", {tagSegment(lineonepos(8), "show_text", "show_text"), tagSegment(lineonepos(18), "", "")}, false, "<hover:show_text:>"),
                tagToken(lineonepos(19), "i", {}, true, "</i>")
            })
            local result, warnings = extractResult(output)

            assert.are.same(minecraftText(lineonepos(1), {showText(lineonepos(1), "", lineonepos(18), "", {plainText(lineonepos(19), "</i>")})}), result)
            assert.are.same({ problem("invalid end tag i", lineonepos(19)) }, warnings)
        end)

        it("expect tags with different tag arguments do not match", function()
            local output = parser.parse({
                tagToken(lineonepos(1), "hover", {tagSegment(lineonepos(8), "show_text", "show_text"), tagSegment(lineonepos(18), "a", "a")}, false, "<hover:show_text:a>"),
                tagToken(lineonepos(20), "hover", {tagSegment(lineonepos(8), "show_text", "show_text"), tagSegment(lineonepos(18), "b", "b")}, true, "</hover:show_text:b>")
            })
            local result, warnings = extractResult(output)

            assert.are.same(minecraftText(lineonepos(1), {showText(lineonepos(1), "a", lineonepos(18), "a", {plainText(lineonepos(20), "</hover:show_text:b>")})}), result)
            assert.are.same({ problem("invalid end tag hover", lineonepos(20)) }, warnings)
        end)

        it("expect tags with same tag arguments match", function()
            local output = parser.parse({
                tagToken(lineonepos(1), "hover", {tagSegment(lineonepos(8), "show_text", "show_text"), tagSegment(lineonepos(18), "a", "a")}, false, "<hover:show_text:a>"),
                plainTextToken(lineonepos(20), "some text"),
                tagToken(lineonepos(29), "hover", {tagSegment(lineonepos(8), "show_text", "show_text"), tagSegment(lineonepos(18), "a", "'a'")}, true, "</hover:show_text:'a'>")
            })
            local result = extractResult(output)
            expectNoWarning(output)
            expectNoStrictProblem(output)

            assert.are.same(minecraftText(lineonepos(1), {showText(lineonepos(1), "a", lineonepos(18), "a", {plainText(lineonepos(20), "some text")})}), result)
        end)

        it("expect end tag with some pecified arguments to match start tag", function()
            local output = parser.parse({
                tagToken(lineonepos(1), "hover", {tagSegment(lineonepos(8), "show_text", "show_text"), tagSegment(lineonepos(18), "a", "a")}, false, "<hover:show_text:a>"),
                plainTextToken(lineonepos(20), "some text"),
                tagToken(lineonepos(29), "hover", {}, true, "</hover:show_text>")
            })
            local result = extractResult(output)
            expectNoWarning(output)
            expectNoStrictProblem(output)

            assert.are.same(minecraftText(lineonepos(1), {showText(lineonepos(1), "a", lineonepos(18), "a", {plainText(lineonepos(20), "some text")})}), result)
        end)

        it("expect end tag with no pecified arguments to match start tag", function()
            local output = parser.parse({
                tagToken(lineonepos(1), "hover", {tagSegment(lineonepos(8), "show_text", "show_text"), tagSegment(lineonepos(18), "a", "a")}, false, "<hover:show_text:a>"),
                plainTextToken(lineonepos(20), "some text"),
                tagToken(lineonepos(29), "hover", {}, true, "</hover>")
            })
            local result = extractResult(output)
            expectNoWarning(output)
            expectNoStrictProblem(output)

            assert.are.same(minecraftText(lineonepos(1), {showText(lineonepos(1), "a", lineonepos(18), "a", {plainText(lineonepos(20), "some text")})}), result)
        end)

        it("expect end tag to close all unclosed tags between itself and the closest previous unclosed tag", function()
            local output = parser.parse({
                tagToken(lineonepos(1), "b", {}, false, "<b>"),
                tagToken(lineonepos(4), "i", {}, false, "<i>"),
                tagToken(lineonepos(7), "u", {}, false, "<u>"),
                plainTextToken(lineonepos(10), "some text"),
                tagToken(lineonepos(19), "i", {}, true, "</i>"),
                plainTextToken(lineonepos(23), "some text")
            })
            local result = extractResult(output)
            expectNoWarning(output)

            assert.are.same(minecraftText(lineonepos(1), {
                decoration(lineonepos(1), "bold", {
                    decoration(lineonepos(4), "italic", {
                        decoration(lineonepos(7), "underlined", {
                            plainText(lineonepos(10), "some text")
                        })
                    }),
                    plainText(lineonepos(23), "some text")
                })
            }), result)
        end)

        it("expect the reset tag to close all unclosed start tags between itself and the beginning of the sequence", function()
            local output = parser.parse({
                tagToken(lineonepos(1), "b", {}, false, "<b>"),
                tagToken(lineonepos(4), "i", {}, false, "<i>"),
                plainTextToken(lineonepos(7), "some text"),
                tagToken(lineonepos(16), "reset", {}, false, "<reset>"),
                tagToken(lineonepos(23), "u", {}, false, "<u>"),
                plainTextToken(lineonepos(26), "some text")
            })
            local result = extractResult(output)
            expectNoWarning(output)

            assert.are.same(minecraftText(lineonepos(1), {
                decoration(lineonepos(1), "bold", {
                    decoration(lineonepos(4), "italic", {
                        plainText(lineonepos(7), "some text")
                    })
                }),
                decoration(lineonepos(23), "underlined", {
                    plainText(lineonepos(26), "some text")
                })
            }), result)
        end)

        it("expect tags unclosed at the end of string is invalid in strict mode", function()
            local output = parser.parse({
                tagToken(lineonepos(1), "b", {}, false, "<b>"),
            })
            local _, _, strictProblems = extractResult(output)

            assert.are.same({ problem("tag b does not have an end tag", lineonepos(1)) }, strictProblems)
        end)

        it("expect tags closed in the wrong order is invalid in strict mode", function()
            local output = parser.parse({
                tagToken(lineonepos(1), "b", {}, false, "<b>"),
                tagToken(lineonepos(4), "i", {}, false, "<i>"),
                tagToken(lineonepos(7), "b", {}, true, "</b>"),
            })
            local _, _, strictProblems = extractResult(output)

            assert.are.same({ problem("tag i does not have an end tag", lineonepos(4)), }, strictProblems)
        end)

    end)

end)

it("expect nodes have correct line and col numbers", function()
    local output = parser.parse({
        plainTextToken(lineonepos(1), "Line 1"),
        newlineToken(lineonepos(7)),
        plainTextToken(position(8, 2, 1), "\\"),
    })
    local result = extractResult(output)
    expectNoWarning(output)
    expectNoStrictProblem(output)

    assert.are.same(minecraftText(lineonepos(1), {
        plainText(lineonepos(1), "Line 1"),
        newline(lineonepos(7)),
        plainText(position(8, 2, 1), "\\"),
    }), result)
end)

