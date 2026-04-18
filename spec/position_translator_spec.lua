local common = require("common")
local parsetree = require("parsetree")
local positionTranslator = require("position_translator")

local function position(index, row, col)
    return common.Position.new(index, row, col)
end

local function lineonepos(index)
    return common.Position.new(index, 1, index)
end

local function problem(message, position)
    return common.Problem.new(message, position)
end

local function minecraftText(position, components)
    return parsetree.MinecraftTextNode.new(position, components)
end

local function namedColor(position, color, components)
    return parsetree.NamedColorNode.new(position, color, components)
end

local function hexColor(position, color, components)
    return parsetree.HexColorNode.new(position, color, components)
end

local function decoration(position, decorationName, components)
    return parsetree.DecorationNode.new(position, decorationName, components)
end

local function showText(position, minecraftText, components)
    return parsetree.ShowTextNode.new(position, minecraftText, components)
end

local function newline(position)
    return parsetree.NewlineNode.new(position)
end

local function plainText(position, content)
    return parsetree.PlainTextNode.new(position, content)
end

describe("position translation", function()

    it("expect local positions on the current line can be translated", function()
        -- test case: <hover:show_text:'hello<br>'>
        -- tag arg string: 'hello<br>'
        -- tag arg content: hello<br>
        local node = minecraftText(lineonepos(1), {plainText(lineonepos(1), "hello"), newline(lineonepos(6))})
        local parentPosition = position(100, 10, 18)
        local originalString = "'hello<br>'"
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(position(101, 10, 19), {plainText(position(101, 10, 19), "hello"), newline(position(106, 10, 24))}), node)
    end)

    it("expect local positions exceeding the current line can be translated", function()
        -- test case: <hover:show_text:'
        -- hello
        -- '>
        -- tag arg string: '\nhello\n'
        -- tag arg content: \nhello\n
        local node = minecraftText(lineonepos(1), {newline(lineonepos(1)), plainText(position(2, 2, 1), "hello"), newline(position(7, 2, 6))})
        local parentPosition = position(100, 10, 18)
        local originalString = "'\nhello\n'"
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(position(101, 10, 19), {newline(position(101, 10, 19)), plainText(position(102, 11, 1), "hello"), newline(position(107, 11, 6))}), node)
    end)

    it("expect local position can be translated when shifted by escapes", function()
        -- test case: <hover:show_text:'\\<br>'>
        -- tag arg string: '\\<br>'
        -- tag arg content: \<br>
        local node = minecraftText(lineonepos(1), {plainText(lineonepos(1), "\\"), newline(lineonepos(2))})
        local parentPosition = lineonepos(18)
        local originalString = "'\\\\<br>'"
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(lineonepos(19), {plainText(lineonepos(19), "\\"), newline(lineonepos(21))}), node)
    end)

end)

describe("node position translation", function()

    it("expect empty string can be translated", function()
        -- test case: <hover:show_text:>
        local node = minecraftText(lineonepos(1), {plainText(lineonepos(1), "")})
        local parentPosition = lineonepos(18)
        local originalString = ""
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(lineonepos(18), {plainText(lineonepos(18), "")}), node)
    end)

    it("expect unquoted string can be translated", function()
        -- test case: <hover:show_text:hello>
        -- tag arg string: hello
        -- tag arg content: hello
        local node = minecraftText(lineonepos(1), {plainText(lineonepos(1), "hello")})
        local parentPosition = lineonepos(18)
        local originalString = "hello"
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(lineonepos(18), {plainText(lineonepos(18), "hello")}), node)
    end)

    it("expect quoted string can be translated", function()
        -- test case: <hover:show_text:'hello'>
        -- tag arg string: 'hello'
        -- tag arg content: hello
        local node = minecraftText(lineonepos(1), {plainText(lineonepos(1), "hello")})
        local parentPosition = lineonepos(18)
        local originalString = "'hello'"
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(lineonepos(19), {plainText(lineonepos(19), "hello")}), node)
    end)

    it("expect empty double quoted string can be translated", function()
        -- test case: <hover:show_text:"hello">
        -- tag arg string: "hello"
        -- tag arg content: hello
        local node = minecraftText(lineonepos(1), {plainText(lineonepos(1), "hello")})
        local parentPosition = lineonepos(18)
        local originalString = '"hello"'
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(lineonepos(19), {plainText(lineonepos(19), "hello")}), node)
    end)

    it("expect newline node can be translated", function()
        -- test case: <hover:show_text:'<br>'>
        -- tag arg string: '<br>'
        -- tag arg content: <br>
        local node = minecraftText(lineonepos(1), {newline(lineonepos(1))})
        local parentPosition = lineonepos(18)
        local originalString = "'<br>'"
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(lineonepos(19), {newline(lineonepos(19))}), node)
    end)

    it("expect named color node can be translated", function()
        -- test case: <hover:show_text:'<green>hello'>
        -- tag arg string: '<green>hello'
        -- tag arg content: <green>hello
        local node = minecraftText(lineonepos(1), {namedColor(lineonepos(1), "green", {plainText(lineonepos(8), "hello")})})
        local parentPosition = lineonepos(18)
        local originalString = "'<green>hello'"
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(lineonepos(19), {namedColor(lineonepos(19), "green", {plainText(lineonepos(26), "hello")})}), node)
    end)

    it("expect hex color node can be translated", function()
        -- test case: <hover:show_text:'<#abcdef>hello'>
        -- tag arg string: '<#abcdef>hello'
        -- tag arg content: <#abcdef>hello
        local node = minecraftText(lineonepos(1), {hexColor(lineonepos(1), "abcdef", {plainText(lineonepos(10), "hello")})})
        local parentPosition = lineonepos(18)
        local originalString = "'<#abcdef>hello'"
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(lineonepos(19), {hexColor(lineonepos(19), "abcdef", {plainText(lineonepos(28), "hello")})}), node)
    end)

    it("expect decoration color node can be translated", function()
        -- test case: <hover:show_text:'<b>hello'>
        -- tag arg string: '<b>hello'
        -- tag arg content: <b>hello
        local node = minecraftText(lineonepos(1), {decoration(lineonepos(1), "bold", {plainText(lineonepos(4), "hello")})})
        local parentPosition = lineonepos(18)
        local originalString = "'<b>hello'"
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(lineonepos(19), {decoration(lineonepos(19), "bold", {plainText(lineonepos(22), "hello")})}), node)
    end)

    it("expect show text node can be translated", function()
        -- test case: <hover:show_text:'<hover:show_text:hello>world'>
        -- tag arg string: '<hover:show_text:hello>world'
        -- tag arg content: <hover:show_text:hello>world
        local innerNode = minecraftText(lineonepos(18), {plainText(lineonepos(18), "hello")})
        local node = minecraftText(lineonepos(1), {showText(lineonepos(1), innerNode, {plainText(lineonepos(24), "world")})})
        local parentPosition = lineonepos(18)
        local originalString = "'<hover:show_text:hello>world'"
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(lineonepos(19), {showText(lineonepos(19), minecraftText(lineonepos(36), {plainText(lineonepos(36), "hello")}), {plainText(lineonepos(42), "world")})}), node)
    end)

    it("expect consecutive nodes can be translated", function()
        -- test case: <hover:show_text:'<green>a</green><br><blue>b</blue>'>
        -- tag arg string: '<green>a</green><br><blue>b</blue>'
        -- tag arg content: <green>a</green><br><blue>b</blue>
        local node = minecraftText(lineonepos(1), {
            namedColor(lineonepos(1), "green", {plainText(lineonepos(8), "a")}),
            newline(lineonepos(17)),
            namedColor(lineonepos(21), "blue", {plainText(lineonepos(27), "b")}),
        })
        local parentPosition = lineonepos(18)
        local originalString = "'<green>a</green><br><blue>b</blue>'"
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(lineonepos(19), {
            namedColor(lineonepos(19), "green", {plainText(lineonepos(26), "a")}),
            newline(lineonepos(35)),
            namedColor(lineonepos(39), "blue", {plainText(lineonepos(45), "b")}),
        }), node)
    end)

    it("expect nested nodes can be translated", function()
        -- test case: <hover:show_text:'<green>a<blue>b<red>c'>
        -- tag arg string: '<green>a<blue>b<red>c'
        -- tag arg content: <green>a<blue>b<red>c
        local node = minecraftText(lineonepos(1), {
            namedColor(lineonepos(1), "green", {
                plainText(lineonepos(8), "a"),
                namedColor(lineonepos(9), "blue", {
                    plainText(lineonepos(15), "b"),
                    namedColor(lineonepos(16), "red", {plainText(lineonepos(21), "c")}),
                }),
            }),
        })
        local parentPosition = lineonepos(18)
        local originalString = "'<green>a<blue>b<red>c'"
        positionTranslator.convertPositions(node, {}, {}, parentPosition, originalString)

        assert.are.same(minecraftText(lineonepos(19), {
            namedColor(lineonepos(19), "green", {
                plainText(lineonepos(26), "a"),
                namedColor(lineonepos(27), "blue", {
                    plainText(lineonepos(33), "b"),
                    namedColor(lineonepos(34), "red", {plainText(lineonepos(39), "c")}),
                }),
            }),
        }), node)
    end)

end)

describe("warnings and strict problems position translation", function()

    it("expect warnings can be translated", function()
        -- test case: <hover:show_text:'<unknown><bad>'>
        local dummyNode = minecraftText(lineonepos(1), {})
        local warnings = {
            problem("unknown tag unknown", lineonepos(1)),
            problem("unknown tag bad", lineonepos(10)),
        }
        local parentPosition = lineonepos(18)
        local originalString = "'<unknown><bad>'"
        positionTranslator.convertPositions(dummyNode, warnings, {}, parentPosition, originalString)

        assert.are.same({
            problem("unknown tag unknown", lineonepos(19)),
            problem("unknown tag bad", lineonepos(28)),
        }, warnings)
    end)

    it("expect strict problems can be translated", function()
        -- test case: <hover:show_text:'<red><blue>'>
        local dummyNode = minecraftText(lineonepos(1), {})
        local strictProblems = {
            problem("tag red does not have an end tag", lineonepos(1)),
            problem("tag blue does not have an end tag", lineonepos(6)),
        }
        local parentPosition = lineonepos(18)
        local originalString = "'<red><blue>'"
        positionTranslator.convertPositions(dummyNode, {}, strictProblems, parentPosition, originalString)

        assert.are.same({
            problem("tag red does not have an end tag", lineonepos(19)),
            problem("tag blue does not have an end tag", lineonepos(24)),
        }, strictProblems)
    end)

end)

