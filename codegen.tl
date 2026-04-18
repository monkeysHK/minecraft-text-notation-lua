local parsetree = require("parsetree")

local record codegen

    generate: function(node: parsetree.Node): string

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

local function genComponents(components: {parsetree.TextComponent}): string
    local result: string = ""

    for _, component in ipairs(components) do
        local generateResult = codegen.generate(component)

        result = result .. generateResult
    end

    return result
end

function codegen.generate(node: parsetree.Node): string
    local result: string = ""

    if node is parsetree.MinecraftTextNode then
        local componentResult = genComponents(node.components)
        result = result .. componentResult


    elseif node is parsetree.PlainTextNode then
        result = result .. node.content

    elseif node is parsetree.NewlineNode then
        result = result .. "<br>"

    elseif node is parsetree.NamedColorNode then
        local componentResult = genComponents(node.components)

        result = result .. span(componentResult, { format = node.color })

    elseif node is parsetree.HexColorNode then
        local componentResult = genComponents(node.components)

        result = result .. span(componentResult, { style = "color: #" .. node.color .. ";" })

    elseif node is parsetree.DecorationNode then
        local componentResult = genComponents(node.components)

        result = result .. span(componentResult, { format = node.decoration })

    elseif node is parsetree.ShowTextNode then
        local tooltipResult = codegen.generate(node.tooltip)

        local mctooltip = span(tooltipResult, { class = "mctooltip" })

        local componentResult = genComponents(node.components)

        result = result .. span(componentResult .. mctooltip, {})

    else
        error("This should not be reached")
    end

    return result
end

return codegen

